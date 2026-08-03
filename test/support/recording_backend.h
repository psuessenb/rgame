#ifndef RGAME_RECORDING_BACKEND_H
#define RGAME_RECORDING_BACKEND_H

#include "backend.h"

/*
 * A drawing backend that records instead of drawing.
 *
 * This is CLAUDE.md's "layer 2": tests assert that the right primitive calls
 * happened, in the right order, with the right vertices — with no window, no GL
 * context and no display. Vertices are *copied* in rather than pointed at, so
 * an assertion stays valid even if the queue that produced them is reset.
 *
 * Test-only code, which is why it lives under test/ rather than in the engine.
 */

typedef enum {
    RGAME_CALL_BEGIN_FRAME,
    RGAME_CALL_SET_CLIP,
    RGAME_CALL_DRAW_BATCH,
    RGAME_CALL_END_FRAME
} rgame_call_kind;

typedef struct {
    rgame_call_kind kind;
    int width, height;             /* begin_frame */
    rgame_rect clip;               /* set_clip */
    unsigned int texture;          /* draw_batch */
    unsigned int first_vertex;     /* draw_batch: index into the recorded copy */
    unsigned int vertex_count;
} rgame_recorded_call;

typedef struct {
    rgame_recorded_call *calls;
    unsigned int count, capacity;
    rgame_vertex *vertices;
    unsigned int vertex_count, vertex_capacity;
} rgame_recording_backend;

void rgame_recording_backend_init(rgame_recording_backend *recorder);
void rgame_recording_backend_destroy(rgame_recording_backend *recorder);

/* The backend interface to hand to rgame_draw_submit. */
rgame_draw_backend rgame_recording_backend_interface(rgame_recording_backend *recorder);

unsigned int rgame_recording_call_count(const rgame_recording_backend *recorder);
const rgame_recorded_call *rgame_recording_call(const rgame_recording_backend *recorder,
                                                unsigned int index);
/* How many calls of one kind were made — the usual "how many draws?" question. */
unsigned int rgame_recording_count_of(const rgame_recording_backend *recorder,
                                      rgame_call_kind kind);
const rgame_vertex *rgame_recording_vertices(const rgame_recording_backend *recorder);

#endif /* RGAME_RECORDING_BACKEND_H */
