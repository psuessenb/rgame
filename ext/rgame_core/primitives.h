#ifndef RGAME_PRIMITIVES_H
#define RGAME_PRIMITIVES_H

#include "canvas.h"
#include "color.h"
#include "texture.h"

/*
 * The shapes a game actually asks for, expressed in the two the canvas knows.
 *
 * A canvas draws triangles and quads. A game draws rectangles, lines, circles
 * and sprites. This module is the translation, and it is pure — every function
 * here turns arguments into `rgame_canvas_*` calls and touches nothing else,
 * so `test/test_primitives.c` can check what a circle produces by reading the
 * draw queue, with no GPU and no window.
 *
 * It sits between the Ruby renderer and the canvas rather than inside either,
 * for the usual reason: a line's corner arithmetic is exactly the kind of thing
 * that is wrong by a factor of two and looks *almost* right, and it should be
 * checkable without a display.
 *
 * ---------------------------------------------------------------------------
 * Corner order
 * ---------------------------------------------------------------------------
 *
 * Everything here hands the canvas its four points in loop order — top-left,
 * top-right, bottom-right, bottom-left — matching `rgame_canvas_quad` and the
 * UV order `rgame_texture_uv` writes. Keeping one order everywhere is what
 * makes textured drawing work without a second convention to translate.
 */

/* An axis-aligned filled rectangle. */
void rgame_prim_rect(rgame_canvas *canvas, float x, float y, float width, float height,
                     rgame_color color, double z);

/*
 * A line of real thickness from (x1,y1) to (x2,y2), as a quad offset
 * perpendicular to its direction. GL's own line width is a suggestion drivers
 * are free to ignore beyond 1px, so a line worth seeing has to be a shape.
 *
 * A zero-length line draws nothing rather than dividing by zero.
 */
void rgame_prim_line(rgame_canvas *canvas, float x1, float y1, float x2, float y2,
                     float thickness, rgame_color color, double z);

/*
 * A filled circle as a fan of `segments` triangles around its centre.
 *
 * The layer being replaced cached a unit-circle *texture* and drew it scaled,
 * because every triangle was a separate draw call there. With a batching queue
 * the fan costs one batch, so the texture — and the render-to-texture support
 * it needed — buys nothing. Fewer than 3 segments draws nothing.
 */
void rgame_prim_circle(rgame_canvas *canvas, float cx, float cy, float radius, int segments,
                       rgame_color color, double z);

/*
 * An image with its *top-left* at (x, y), at its natural size. This is the
 * backdrop case: no rotation, no scale, nothing to decide.
 */
void rgame_prim_image(rgame_canvas *canvas, const rgame_texture *view, float x, float y,
                      rgame_color color, double z);

/*
 * An image *centred* on (cx, cy), rotated `angle_degrees` clockwise about that
 * centre and uniformly scaled — the sprite case, and the shape the layer being
 * replaced exposed as `draw_rot`.
 *
 * The rotation goes through the canvas's own transform stack rather than a
 * second sin/cos here, so there is exactly one place in the engine that decides
 * which way a positive angle turns. An unrotated, unscaled image skips the
 * stack entirely and emits the quad directly.
 */
void rgame_prim_image_rot(rgame_canvas *canvas, const rgame_texture *view, float cx, float cy,
                          float angle_degrees, float scale, rgame_color color, double z);

#endif /* RGAME_PRIMITIVES_H */
