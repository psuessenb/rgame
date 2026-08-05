#ifndef RGAME_BACKEND_H
#define RGAME_BACKEND_H

#include "graphics/clip.h"
#include "graphics/draw_queue.h"

/*
 * The drawing backend seam — "layer 2" in CLAUDE.md's abstraction strategy.
 *
 * Everything up to here is arithmetic: the canvas positions vertices, the queue
 * sorts and batches them. This is where that stops and real GL calls begin, so
 * this is where the function-pointer table goes — added at the point real calls
 * appear rather than speculatively ahead of it.
 *
 * Two implementations exist by design: the real one that talks to OpenGL, and a
 * recording one the Check suite substitutes to assert that the right primitive
 * calls happened in the right order, with no display anywhere in sight.
 *
 * ---------------------------------------------------------------------------
 * What the seam is *not* for
 * ---------------------------------------------------------------------------
 *
 * It is not how the queue and canvas get tested. Those hand back their prepared
 * batches directly and are exercised without any backend at all, which keeps
 * the dependency one-directional: draw_queue and canvas do not include this
 * header. What is genuinely worth a fake is the submit loop below — the small
 * amount of logic that sits between a prepared frame and the GPU.
 */

/*
 * Every member may be NULL, in which case that call is skipped. `ctx` is the
 * implementation's own state, passed back to each function.
 *
 * Fixed arity throughout, like the app callbacks: a variadic convention on a
 * per-frame path marshals arguments for no benefit.
 */
typedef struct {
    void (*begin_frame)(void *ctx, int width, int height);
    void (*set_clip)(void *ctx, rgame_rect clip);
    void (*draw_batch)(void *ctx, unsigned int texture, const rgame_vertex *vertices,
                       unsigned int count);
    void (*end_frame)(void *ctx);
    void *ctx;
} rgame_draw_backend;

/*
 * Walks a *prepared* queue and drives the backend:
 *
 *     begin_frame
 *       set_clip / draw_batch ... (per batch, clip only when it changes)
 *     end_frame
 *
 * `set_clip` is issued only when the rectangle actually differs from the last
 * one set. Batches split on either texture or clip, so two adjacent batches
 * often share a clip and differ only in texture — re-issuing an identical
 * scissor for each would be a wasted state change every frame.
 *
 * begin_frame and end_frame are called even for an empty queue: the real
 * backend still has to clear and present the frame.
 */
void rgame_draw_submit(const rgame_draw_queue *queue, const rgame_draw_backend *backend,
                       int width, int height);

#endif /* RGAME_BACKEND_H */
