/*
 * primitives.c — rectangles, lines, circles and images, in terms of the
 * canvas's triangles and quads. Pure; see primitives.h.
 */

#include "graphics/primitives.h"

#include <math.h>

/* math.h only promises M_PI under POSIX, and -std=c17 asks for strict ISO C,
 * which hides it. Spelling it out here is one line and portable. */
#define RGAME_TWO_PI 6.283185307179586f

void rgame_prim_rect(rgame_canvas *canvas, float x, float y, float width, float height,
                     rgame_color color, double z) {
    float xy8[8] = {
        x, y,
        x + width, y,
        x + width, y + height,
        x, y + height,
    };
    rgame_canvas_quad(canvas, xy8, color, z);
}

void rgame_prim_line(rgame_canvas *canvas, float x1, float y1, float x2, float y2,
                     float thickness, rgame_color color, double z) {
    float dx = x2 - x1;
    float dy = y2 - y1;
    float length = sqrtf((dx * dx) + (dy * dy));
    if (length == 0.0f) {
        return;
    }

    /* Half the thickness, perpendicular to the direction of travel. Rotating a
     * vector by 90 degrees swaps its components and negates one, which is where
     * (dy, dx) comes from — and why the two corners on each end use opposite
     * signs. */
    float scale = (thickness / 2.0f) / length;
    float ox = dy * scale;
    float oy = dx * scale;

    /* Loop order around the quad: the two corners at the start, then the two at
     * the end, coming back along the other side. Listing them 1a, 2a, 2b, 1b
     * (rather than 1a, 1b, 2a, 2b) is what keeps it a rectangle instead of an
     * hourglass. */
    float xy8[8] = {
        x1 - ox, y1 + oy,
        x2 - ox, y2 + oy,
        x2 + ox, y2 - oy,
        x1 + ox, y1 - oy,
    };
    rgame_canvas_quad(canvas, xy8, color, z);
}

void rgame_prim_circle(rgame_canvas *canvas, float cx, float cy, float radius, int segments,
                       rgame_color color, double z) {
    if (segments < 3 || radius <= 0.0f) {
        return;
    }

    float step = RGAME_TWO_PI / (float)segments;
    for (int i = 0; i < segments; i++) {
        float a0 = step * (float)i;
        float a1 = step * (float)(i + 1);

        /* Every wedge starts at the centre, so the fan closes exactly: the last
         * wedge's far edge is computed from segment count, not accumulated, and
         * cannot drift into a visible gap. */
        float xy6[6] = {
            cx, cy,
            cx + (cosf(a0) * radius), cy + (sinf(a0) * radius),
            cx + (cosf(a1) * radius), cy + (sinf(a1) * radius),
        };
        rgame_canvas_triangle(canvas, xy6, color, z);
    }
}

/*
 * The four corners of `width` x `height` at (x, y), plus the view's texture
 * coordinates, in the one corner order everything here uses.
 *
 * `flip_x`/`flip_y` mirror the *coordinates*, not the geometry: the corners are
 * in loop order — TL, TR, BR, BL — so a horizontal mirror exchanges the `u` of
 * the two top corners and of the two bottom ones. Doing it here rather than by
 * handing in a negative width is what keeps the drawn rectangle exactly where
 * the caller put it.
 */
static void textured_rect(rgame_canvas *canvas, const rgame_texture *view, float x, float y,
                          float width, float height, int flip_x, int flip_y, rgame_color color,
                          double z) {
    float xy8[8] = {
        x, y,
        x + width, y,
        x + width, y + height,
        x, y + height,
    };
    float uv8[8];
    rgame_texture_uv(view, uv8);

    float swap;
    if (flip_x) {
        swap = uv8[0]; uv8[0] = uv8[2]; uv8[2] = swap; /* u of TL and TR */
        swap = uv8[6]; uv8[6] = uv8[4]; uv8[4] = swap; /* u of BL and BR */
    }
    if (flip_y) {
        swap = uv8[1]; uv8[1] = uv8[7]; uv8[7] = swap; /* v of TL and BL */
        swap = uv8[3]; uv8[3] = uv8[5]; uv8[5] = swap; /* v of TR and BR */
    }

    rgame_canvas_textured_quad(canvas, rgame_texture_name(view), xy8, uv8, color, z);
}

void rgame_prim_glyph(rgame_canvas *canvas, unsigned int texture, rgame_rect source,
                      int page_width, int page_height, float x, float y, rgame_color color,
                      double z) {
    if (source.w <= 0 || source.h <= 0 || page_width <= 0 || page_height <= 0) {
        return;
    }

    float xy8[8] = {
        x, y,
        x + (float)source.w, y,
        x + (float)source.w, y + (float)source.h,
        x, y + (float)source.h,
    };

    /* Normalised against the page, not the glyph — the same division
     * rgame_texture_uv does, for the same reason: dividing by the glyph's own
     * size would stretch every letter across the whole page. */
    float u0 = (float)source.x / (float)page_width;
    float v0 = (float)source.y / (float)page_height;
    float u1 = (float)(source.x + source.w) / (float)page_width;
    float v1 = (float)(source.y + source.h) / (float)page_height;

    float uv8[8] = { u0, v0, u1, v0, u1, v1, u0, v1 };

    rgame_canvas_textured_quad(canvas, texture, xy8, uv8, color, z);
}

void rgame_prim_image(rgame_canvas *canvas, const rgame_texture *view, float x, float y,
                      rgame_color color, double z) {
    rgame_prim_image_scaled(canvas, view, x, y, 1.0f, 1.0f, color, z);
}

void rgame_prim_image_scaled(rgame_canvas *canvas, const rgame_texture *view, float x, float y,
                             float scale_x, float scale_y, rgame_color color, double z) {
    if (!view || !view->sheet || scale_x == 0.0f || scale_y == 0.0f) {
        return;
    }

    /* The sign selects the mirror and the magnitude the size, so the rectangle
     * is always well-formed and the caller never has to work out which corner
     * the arithmetic landed on. */
    textured_rect(canvas, view, x, y, (float)rgame_texture_width(view) * fabsf(scale_x),
                  (float)rgame_texture_height(view) * fabsf(scale_y), scale_x < 0.0f,
                  scale_y < 0.0f, color, z);
}

void rgame_prim_image_rot(rgame_canvas *canvas, const rgame_texture *view, float cx, float cy,
                          float angle_degrees, float scale, rgame_color color, double z) {
    if (!view || !view->sheet) {
        return;
    }

    float width = (float)rgame_texture_width(view);
    float height = (float)rgame_texture_height(view);

    /* The common case — a sprite drawn upright at its natural size — is one
     * quad and no stack traffic at all. */
    if (angle_degrees == 0.0f && scale == 1.0f) {
        textured_rect(canvas, view, cx - (width / 2.0f), cy - (height / 2.0f), width, height, 0,
                      0, color, z);
        return;
    }

    /* Otherwise place the quad at the origin and move the *world* to it:
     * translate to the centre, rotate about it, scale. Reusing the transform
     * stack means the direction a positive angle turns is decided in exactly
     * one place (transform.c), not re-derived here with a sign to get wrong. */
    rgame_canvas_push_translate(canvas, cx, cy);
    rgame_canvas_push_rotate(canvas, angle_degrees, 0.0f, 0.0f);
    rgame_canvas_push_scale(canvas, scale, scale);

    textured_rect(canvas, view, -width / 2.0f, -height / 2.0f, width, height, 0, 0, color, z);

    rgame_canvas_pop(canvas);
    rgame_canvas_pop(canvas);
    rgame_canvas_pop(canvas);
}
