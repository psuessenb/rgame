#ifndef RGAME_DRAW_QUEUE_H
#define RGAME_DRAW_QUEUE_H

#include "clip.h"

/*
 * The draw queue: z-ordering and batching — pure arithmetic, no SDL, no GL.
 *
 * ---------------------------------------------------------------------------
 * Why this exists at all
 * ---------------------------------------------------------------------------
 *
 * Every draw call carries a `z`, and the renderer must sort by it *regardless
 * of the order the calls were made in*. UI draws above gameplay, overlays above
 * UI, all by z value rather than by anyone remembering to draw in the right
 * sequence. The layer being replaced depends on this everywhere.
 *
 * The obvious shortcut — enable the depth buffer and let the GPU sort it out —
 * does not work here, and it is worth being clear why: depth testing and alpha
 * blending are mutually exclusive. A depth-tested translucent quad *rejects*
 * the fragments behind it instead of blending with them, so anything drawn
 * later at a lower z simply vanishes. Every UI panel in this engine is
 * translucent chrome over gameplay, so the depth buffer would break exactly the
 * case it was supposed to help. Hence: collect commands, sort them on the CPU,
 * and draw back-to-front with blending on.
 *
 * ---------------------------------------------------------------------------
 * How it is arranged
 * ---------------------------------------------------------------------------
 *
 * Vertices go in one big array; commands index into it. That keeps the records
 * being sorted small (a command is ~40 bytes, not six vertices), and lets
 * triangles and quads sit in the same queue without a variant type.
 *
 * `prepare` then does two things: sorts the commands, and walks them building a
 * *second*, sorted vertex array plus a list of batches. The copy is necessary —
 * after sorting, a batch's commands are adjacent but their vertices are still
 * scattered through the original array, and a GL draw call needs one contiguous
 * run.
 *
 * Nothing here talks to a backend. `prepare` leaves batches and vertices for
 * someone else to walk, which keeps the dependency one-directional and means
 * the whole module is testable with no fake and no display.
 */

/*
 * One vertex, 20 bytes: position, texture coordinate, colour.
 *
 * The colour is four *bytes* in R, G, B, A order rather than a packed 32-bit
 * word, and that is deliberate. glColorPointer(4, GL_UNSIGNED_BYTE, ...) reads
 * them in memory order, and the bytes of a packed 0xRRGGBBAA come out A, B, G,
 * R on a little-endian machine — GL would read alpha as red. Storing bytes
 * sidesteps the question and is endian-independent. See rgame_color_bytes.
 */
typedef struct {
    float x, y; /* screen space: already transformed when it arrives here */
    float u, v; /* texture coordinates; ignored when texture == 0 */
    unsigned char rgba[4];
} rgame_vertex;

typedef struct {
    double z;
    /*
     * Insertion index. The sort compares (z, order), so commands with equal z
     * keep the order they were issued in — Gosu behaves that way, and without
     * it same-z sprites would swap places between frames as the sort reshuffled
     * them, which reads as flicker. Note the *comparator* provides stability
     * here, so the sort algorithm itself does not have to be stable.
     */
    unsigned int order;
    unsigned int texture; /* GL texture name; 0 means untextured */
    /*
     * The clip travels with the command rather than being ambient state,
     * because sorting reorders commands across viewports. A clip left "current"
     * at draw time would end up scissoring whichever quads happened to sort
     * next to it — the bug a single-viewport renderer cannot see and cannot fix
     * without being rebuilt.
     */
    rgame_rect clip;
    unsigned int first_vertex, vertex_count;
} rgame_draw_command;

/* A run of adjacent sorted commands that share a texture and a clip, and can
 * therefore go to the GPU as one call. */
typedef struct {
    unsigned int texture;
    rgame_rect clip;
    unsigned int first_vertex, vertex_count; /* into the prepared vertex array */
} rgame_draw_batch;

typedef struct {
    rgame_draw_command *commands;
    unsigned int command_count, command_capacity;

    rgame_vertex *vertices; /* as submitted */
    unsigned int vertex_count, vertex_capacity;

    rgame_vertex *sorted; /* rebuilt by prepare, contiguous per batch */
    unsigned int sorted_count, sorted_capacity;

    rgame_draw_batch *batches;
    unsigned int batch_count, batch_capacity;

    /*
     * Where vertices go when a command is dropped (empty clip, or a failed
     * grow). The caller still gets somewhere writable, so it never has to
     * null-check and can never write through a null pointer; the vertices are
     * simply never referenced. Bounded by the largest single request.
     */
    rgame_vertex *discard;
    unsigned int discard_capacity;
} rgame_draw_queue;

void rgame_draw_queue_init(rgame_draw_queue *queue);

/* Releases every buffer. The queue is reusable after a fresh init. */
void rgame_draw_queue_destroy(rgame_draw_queue *queue);

/*
 * Empties the queue for a new frame while *keeping* the buffers it has grown.
 * After a few frames the capacities settle and a steady frame allocates
 * nothing at all, which is the difference between a smooth 60fps and a GC-style
 * hitch every time the heap grows.
 */
void rgame_draw_queue_reset(rgame_draw_queue *queue);

/*
 * Reserves `count` vertices for one primitive and returns a writable span for
 * the caller to fill in place — no temporary array, no copy.
 *
 * Never returns NULL. A command with an empty clip, a zero vertex count, or one
 * that could not be stored is silently dropped, and the returned span points at
 * scratch. That is deliberate: a caller that forgets to check a return value
 * should get a draw that does not appear, not a crash.
 */
rgame_vertex *rgame_draw_queue_alloc(rgame_draw_queue *queue, unsigned int count, double z,
                                     unsigned int texture, rgame_rect clip);

/*
 * Sorts the commands and builds the batch list and the contiguous vertex array
 * that goes with it. Call once per frame, after all drawing and before handing
 * the result to a backend.
 */
void rgame_draw_queue_prepare(rgame_draw_queue *queue);

/* Valid after prepare. */
unsigned int rgame_draw_queue_batch_count(const rgame_draw_queue *queue);
const rgame_draw_batch *rgame_draw_queue_batch(const rgame_draw_queue *queue,
                                               unsigned int index);
const rgame_vertex *rgame_draw_queue_vertices(const rgame_draw_queue *queue);
unsigned int rgame_draw_queue_vertex_count(const rgame_draw_queue *queue);

/*
 * The ordering `prepare` sorts by: ascending z, ties broken by insertion order.
 *
 * Exposed rather than kept static because it cannot be tested through the
 * sort: the C library's qsort is free to be stable, and glibc's is, so a
 * missing tiebreak would still *look* correct here while being undefined
 * anywhere else. Signature matches qsort's comparator.
 */
int rgame_draw_command_compare(const void *lhs, const void *rhs);

/* How many commands are waiting. Mostly for tests and diagnostics. */
unsigned int rgame_draw_queue_command_count(const rgame_draw_queue *queue);

/*
 * Current buffer capacities. Exposed so a test can assert that a second
 * identical frame grows nothing — the "no per-frame allocation" property is
 * invisible otherwise, and would rot without something watching it.
 */
unsigned int rgame_draw_queue_command_capacity(const rgame_draw_queue *queue);
unsigned int rgame_draw_queue_vertex_capacity(const rgame_draw_queue *queue);

#endif /* RGAME_DRAW_QUEUE_H */
