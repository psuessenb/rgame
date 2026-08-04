#ifndef RGAME_RECORDING_H
#define RGAME_RECORDING_H

#include "draw_queue.h"

/*
 * A baked block of drawing, kept between frames and replayed as a few calls.
 *
 * The problem it solves is the tile map. A screen of 16px tiles is a couple of
 * thousand quads, and while the batching queue already merges them into one GL
 * call, the *CPU* still walks every tile, transforms four corners and appends a
 * command — sixty times a second, for a layer that has not changed since the
 * level loaded.
 *
 * A recording captures that work once. What comes out is the finished vertex
 * array, already sorted and grouped by texture, so replaying it is one command
 * per texture instead of one per tile:
 *
 *     bake once      2000 tiles -> 2000 commands -> 1 batch
 *     replay         1 command  -> 1 batch, every frame
 *
 * ---------------------------------------------------------------------------
 * What is captured, and what is not
 * ---------------------------------------------------------------------------
 *
 * Positions and texture coordinates are baked. Transforms *inside* the recorded
 * block are baked with them — a rotated sprite records its rotated corners —
 * and the transform in effect at *replay* time is applied on top, which is what
 * lets a baked layer scroll under a camera.
 *
 * Clips are not captured at all: a batch carries a texture and a span of
 * vertices, and nothing else. Clipping happens at rasterisation, so it cannot
 * be baked into a vertex, and a clip rectangle recorded in one place would be
 * wrong everywhere the recording is later replayed. Pushing a clip inside a
 * recorded block is therefore refused rather than silently dropped; clip the
 * *replay* instead, which does exactly what the caller meant.
 *
 * Colours are baked, but a replay may tint them — multiplying each recorded
 * component by the tint's. The layer being replaced could not do this (its
 * recorded images drew white-only, and callers worked around it); there is no
 * reason to inherit the limitation.
 */

/* A run of recorded vertices sharing one texture — one GL call's worth. */
typedef struct {
    unsigned int texture; /* 0 means untextured */
    unsigned int first_vertex, vertex_count;
} rgame_recording_batch;

/* Tagged so the public header can forward-declare the same type without
 * seeing what is in it — src/main.c and the Ruby binding only ever hold a
 * pointer. */
typedef struct rgame_recording {
    rgame_vertex *vertices; /* in painter order, grouped by batch */
    unsigned int vertex_count;

    rgame_recording_batch *batches;
    unsigned int batch_count;
} rgame_recording;

/*
 * Copies a *prepared* draw queue into `out`, which must be uninitialised or
 * already destroyed. Returns 1 on success, 0 if out of memory — in which case
 * `out` is left empty and is still safe to destroy.
 *
 * "Prepared" means rgame_draw_queue_prepare has run: the sorting and grouping
 * is exactly the work being saved, so a recording captures its result rather
 * than the raw command list.
 *
 * An empty queue records successfully and replays as nothing.
 */
int rgame_recording_capture(rgame_recording *out, const rgame_draw_queue *queue);

/* Frees the buffers. Safe on a zeroed struct, and safe to call twice. */
void rgame_recording_destroy(rgame_recording *recording);

unsigned int rgame_recording_batch_count(const rgame_recording *recording);
unsigned int rgame_recording_vertex_count(const rgame_recording *recording);

/*
 * The bounding box of everything recorded, in the recording's own coordinates.
 * Zero-sized for an empty recording. Games use it to decide whether a baked
 * layer is on screen at all before replaying it.
 */
void rgame_recording_bounds(const rgame_recording *recording, float *min_x, float *min_y,
                            float *max_x, float *max_y);

#endif /* RGAME_RECORDING_H */
