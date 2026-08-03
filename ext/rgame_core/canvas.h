#ifndef RGAME_CANVAS_H
#define RGAME_CANVAS_H

#include "backend.h"
#include "clip.h"
#include "color.h"
#include "draw_queue.h"
#include "transform.h"

/*
 * The canvas: where the transform stack, the clip stack and the draw queue meet
 * — and still pure arithmetic, with no SDL and no GL.
 *
 * Each of the three pieces below it does one thing and knows nothing of the
 * others. This is the layer that composes them, and it is the seam the drawing
 * API is actually written against: everything above (the Ruby renderer, and
 * eventually the scene graph) speaks to a canvas, and everything below is
 * arithmetic that can be tested without a window.
 *
 * ---------------------------------------------------------------------------
 * Vertices are transformed on the way in
 * ---------------------------------------------------------------------------
 *
 * A primitive's points are mapped through the current transform *before* they
 * reach the queue, so the queue stores screen-space coordinates. That is what
 * lets it sort freely: once a vertex is positioned, reordering commands cannot
 * change where anything lands. Storing untransformed points and applying the
 * transform at flush time would mean re-associating each command with the
 * transform that was current when it was issued — which is exactly the
 * bookkeeping this design exists to avoid.
 *
 * ---------------------------------------------------------------------------
 * Clips are transformed too
 * ---------------------------------------------------------------------------
 *
 * A clip pushed inside a translate moves with it — measured against the layer
 * being replaced, where a clip at x 0..20 inside a translate of 50 clips
 * x 50..70. So `push_clip` maps the caller's rect through the current transform
 * before handing it to the clip stack, which works purely in screen space.
 *
 * Under translation and scaling that mapping is exact. Under rotation it cannot
 * be: a scissor rectangle is axis-aligned and a rotated rectangle is not, so
 * the axis-aligned bounding box is used instead. That errs towards clipping
 * *less* than asked, which is the safe direction, and nothing in the engine
 * rotates a clip today.
 *
 * ---------------------------------------------------------------------------
 * One pop for any push
 * ---------------------------------------------------------------------------
 *
 * `push_translate`, `push_rotate`, `push_scale` and `push_clip` are all undone
 * by the same `pop`. The canvas remembers which stack each push went to, so a
 * caller never has to — and cannot pop the wrong one. Pushes that could not be
 * honoured (a full stack) are still counted, so pop stays balanced and the
 * drawing comes out untransformed rather than desynchronised.
 */

/* Deep enough that it cannot fill before both underlying stacks have; pushes
 * beyond that are counted rather than recorded, so balance always holds. */
#define RGAME_CANVAS_STACK_DEPTH (RGAME_TRANSFORM_STACK_DEPTH + RGAME_CLIP_STACK_DEPTH)

typedef struct {
    rgame_transform_stack transforms;
    rgame_clip_stack clips;
    rgame_draw_queue queue;

    /* Which stack each outstanding push went to, so pop can undo the right one. */
    unsigned char pushes[RGAME_CANVAS_STACK_DEPTH];
    int push_depth;
    /* Pushes with nowhere to be recorded. Counted so pop still balances. */
    int unrecorded_pushes;

    /* Remembered from begin_frame, so submit needs no repeat of the size. */
    int width, height;
} rgame_canvas;

void rgame_canvas_init(rgame_canvas *canvas);
void rgame_canvas_destroy(rgame_canvas *canvas);

/*
 * Starts a frame: empties the queue (keeping its buffers), resets both stacks,
 * and sets the clip base to the window. Re-stating the size every frame is also
 * how a resize takes effect, so there is no separate path to forget.
 */
void rgame_canvas_begin_frame(rgame_canvas *canvas, int width, int height);

/* Sorts and batches what was drawn. Read the result through rgame_canvas_queue. */
void rgame_canvas_end_frame(rgame_canvas *canvas);

void rgame_canvas_push_translate(rgame_canvas *canvas, float dx, float dy);
void rgame_canvas_push_rotate(rgame_canvas *canvas, float degrees, float pivot_x,
                              float pivot_y);
void rgame_canvas_push_scale(rgame_canvas *canvas, float sx, float sy);

/* `rect` is in the caller's local coordinates and is mapped through the current
 * transform before narrowing the clip. */
void rgame_canvas_push_clip(rgame_canvas *canvas, rgame_rect rect);

void rgame_canvas_pop(rgame_canvas *canvas);

/*
 * Primitives. Points arrive as flat coordinate pairs in the caller's local
 * space: `xy6` is three points, `xy8` four. A quad's points are taken in loop
 * order (for a rectangle: top-left, top-right, bottom-right, bottom-left) and
 * split into triangles 0-1-2 and 0-2-3.
 *
 * `uv8` is the matching four texture coordinates, in the same corner order.
 */
void rgame_canvas_triangle(rgame_canvas *canvas, const float *xy6, rgame_color color,
                           double z);
void rgame_canvas_quad(rgame_canvas *canvas, const float *xy8, rgame_color color, double z);
void rgame_canvas_textured_quad(rgame_canvas *canvas, unsigned int texture, const float *xy8,
                                const float *uv8, rgame_color color, double z);

/*
 * Hands the finished frame to a backend. Call after end_frame; equivalent to
 * rgame_draw_submit with the size this frame was begun at.
 */
void rgame_canvas_submit(const rgame_canvas *canvas, const rgame_draw_backend *backend);

const rgame_draw_queue *rgame_canvas_queue(const rgame_canvas *canvas);

/* How many pushes are outstanding, counting ones that could not be recorded.
 * A balanced frame ends at zero. */
int rgame_canvas_depth(const rgame_canvas *canvas);

#endif /* RGAME_CANVAS_H */
