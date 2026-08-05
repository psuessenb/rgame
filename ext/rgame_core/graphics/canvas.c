#include "graphics/canvas.h"

#include <math.h>

/* What a recorded push has to undo. */
enum {
    RGAME_PUSH_TRANSFORM,
    RGAME_PUSH_CLIP,
    /* The underlying stack was full. Nothing to undo, but it still occupies a
     * slot so that the caller's matching pop stays paired with this push. */
    RGAME_PUSH_NOTHING
};

void rgame_canvas_init(rgame_canvas *canvas) {
    rgame_draw_queue_init(&canvas->queue);
    rgame_transform_stack_init(&canvas->transforms);
    rgame_clip_stack_init(&canvas->clips, 0, 0);
    canvas->push_depth = 0;
    canvas->unrecorded_pushes = 0;
    canvas->width = 0;
    canvas->height = 0;
}

void rgame_canvas_destroy(rgame_canvas *canvas) {
    rgame_draw_queue_destroy(&canvas->queue);
}

void rgame_canvas_begin_frame(rgame_canvas *canvas, int width, int height) {
    rgame_draw_queue_reset(&canvas->queue);
    rgame_transform_stack_init(&canvas->transforms);
    rgame_clip_stack_init(&canvas->clips, width, height);
    canvas->push_depth = 0;
    canvas->unrecorded_pushes = 0;
    canvas->width = width;
    canvas->height = height;
}

void rgame_canvas_end_frame(rgame_canvas *canvas) {
    rgame_draw_queue_prepare(&canvas->queue);
}

/* Records what a successful push has to undo. Returns 0 when there is no room
 * to record it, in which case the caller counts it as unrecorded instead. */
static int record_push(rgame_canvas *canvas, unsigned char kind) {
    if (canvas->push_depth >= RGAME_CANVAS_STACK_DEPTH) {
        return 0;
    }
    canvas->pushes[canvas->push_depth++] = kind;
    return 1;
}

/*
 * Shared tail of every push: if the underlying stack accepted it, remember
 * which one to undo; otherwise remember that there is nothing to undo. Either
 * way a push is accounted for, so pop always has something to consume.
 */
static void account_push(rgame_canvas *canvas, int accepted, unsigned char kind) {
    if (!record_push(canvas, accepted ? kind : RGAME_PUSH_NOTHING)) {
        canvas->unrecorded_pushes++;
    }
}

void rgame_canvas_push_translate(rgame_canvas *canvas, float dx, float dy) {
    int ok = rgame_transform_push_translate(&canvas->transforms, dx, dy);
    account_push(canvas, ok, RGAME_PUSH_TRANSFORM);
}

void rgame_canvas_push_rotate(rgame_canvas *canvas, float degrees, float pivot_x,
                              float pivot_y) {
    int ok = rgame_transform_push_rotate(&canvas->transforms, degrees, pivot_x, pivot_y);
    account_push(canvas, ok, RGAME_PUSH_TRANSFORM);
}

void rgame_canvas_push_scale(rgame_canvas *canvas, float sx, float sy) {
    int ok = rgame_transform_push_scale(&canvas->transforms, sx, sy);
    account_push(canvas, ok, RGAME_PUSH_TRANSFORM);
}

/*
 * Maps a rect through the current transform and takes the axis-aligned bounding
 * box of the result.
 *
 * All four corners are mapped, not just two: under rotation the box is decided
 * by whichever corners happen to be extreme, and under a mirroring scale the
 * "top-left" corner is no longer top-left. Bounds are rounded outwards so a
 * partially covered pixel is kept rather than clipped away.
 */
static rgame_rect transformed_bounds(const rgame_canvas *canvas, rgame_rect rect) {
    float corners[4][2] = { { (float)rect.x, (float)rect.y },
                            { (float)(rect.x + rect.w), (float)rect.y },
                            { (float)(rect.x + rect.w), (float)(rect.y + rect.h) },
                            { (float)rect.x, (float)(rect.y + rect.h) } };

    float min_x = 0.0f, min_y = 0.0f, max_x = 0.0f, max_y = 0.0f;
    for (int i = 0; i < 4; i++) {
        float x, y;
        rgame_transform_apply(&canvas->transforms, corners[i][0], corners[i][1], &x, &y);
        if (i == 0) {
            min_x = max_x = x;
            min_y = max_y = y;
            continue;
        }
        if (x < min_x) {
            min_x = x;
        }
        if (x > max_x) {
            max_x = x;
        }
        if (y < min_y) {
            min_y = y;
        }
        if (y > max_y) {
            max_y = y;
        }
    }

    int left = (int)floorf(min_x);
    int top = (int)floorf(min_y);
    int right = (int)ceilf(max_x);
    int bottom = (int)ceilf(max_y);
    return rgame_rect_make(left, top, right - left, bottom - top);
}

void rgame_canvas_push_clip(rgame_canvas *canvas, rgame_rect rect) {
    int ok = rgame_clip_push(&canvas->clips, transformed_bounds(canvas, rect));
    account_push(canvas, ok, RGAME_PUSH_CLIP);
}

void rgame_canvas_pop(rgame_canvas *canvas) {
    /* Unrecorded pushes unwind first: they are the most recent ones, since a
     * push is only left unrecorded once the record stack is already full. */
    if (canvas->unrecorded_pushes > 0) {
        canvas->unrecorded_pushes--;
        return;
    }
    if (canvas->push_depth == 0) {
        return; /* unbalanced pop; harmless */
    }

    switch (canvas->pushes[--canvas->push_depth]) {
    case RGAME_PUSH_TRANSFORM:
        rgame_transform_pop(&canvas->transforms);
        break;
    case RGAME_PUSH_CLIP:
        rgame_clip_pop(&canvas->clips);
        break;
    default:
        break; /* RGAME_PUSH_NOTHING: the push never took effect */
    }
}

/* Fills one vertex: map the point into screen space, copy through the texture
 * coordinate, and write the colour as the four bytes GL reads. */
static void write_vertex(const rgame_canvas *canvas, rgame_vertex *vertex, float x, float y,
                         float u, float v, rgame_color color) {
    rgame_transform_apply(&canvas->transforms, x, y, &vertex->x, &vertex->y);
    vertex->u = u;
    vertex->v = v;
    rgame_color_bytes(color, vertex->rgba);
}

void rgame_canvas_triangle(rgame_canvas *canvas, const float *xy6, rgame_color color,
                           double z) {
    rgame_vertex *out = rgame_draw_queue_alloc(&canvas->queue, 3, z, 0,
                                               rgame_clip_current(&canvas->clips));
    for (int i = 0; i < 3; i++) {
        write_vertex(canvas, &out[i], xy6[i * 2], xy6[(i * 2) + 1], 0.0f, 0.0f, color);
    }
}

/* Corner indices for the two triangles a quad becomes. */
static const int RGAME_QUAD_TRIANGLES[6] = { 0, 1, 2, 0, 2, 3 };

void rgame_canvas_quad(rgame_canvas *canvas, const float *xy8, rgame_color color, double z) {
    rgame_vertex *out = rgame_draw_queue_alloc(&canvas->queue, 6, z, 0,
                                               rgame_clip_current(&canvas->clips));
    for (int i = 0; i < 6; i++) {
        int corner = RGAME_QUAD_TRIANGLES[i];
        write_vertex(canvas, &out[i], xy8[corner * 2], xy8[(corner * 2) + 1], 0.0f, 0.0f,
                     color);
    }
}

void rgame_canvas_textured_quad(rgame_canvas *canvas, unsigned int texture, const float *xy8,
                                const float *uv8, rgame_color color, double z) {
    rgame_vertex *out = rgame_draw_queue_alloc(&canvas->queue, 6, z, texture,
                                               rgame_clip_current(&canvas->clips));
    for (int i = 0; i < 6; i++) {
        int corner = RGAME_QUAD_TRIANGLES[i];
        write_vertex(canvas, &out[i], xy8[corner * 2], xy8[(corner * 2) + 1], uv8[corner * 2],
                     uv8[(corner * 2) + 1], color);
    }
}

/* Multiplies two colour components, 0..255 in and out: 255 leaves the other
 * untouched, which is what makes WHITE the "no tint" value. */
static unsigned char modulate(unsigned char value, int tint) {
    return (unsigned char)((value * tint) / 255);
}

void rgame_canvas_replay(rgame_canvas *canvas, const rgame_recording *recording, float dx,
                         float dy, rgame_color color, double z) {
    if (!recording) {
        return;
    }

    int tint[4] = { rgame_color_r(color), rgame_color_g(color), rgame_color_b(color),
                    rgame_color_a(color) };

    for (unsigned int b = 0; b < recording->batch_count; b++) {
        const rgame_recording_batch *batch = &recording->batches[b];

        /* One command per baked batch, rather than one per original draw call:
         * the whole point of a recording is that the per-tile work happened
         * once, at bake time. */
        rgame_vertex *out = rgame_draw_queue_alloc(&canvas->queue, batch->vertex_count, z,
                                                   batch->texture,
                                                   rgame_clip_current(&canvas->clips));

        for (unsigned int i = 0; i < batch->vertex_count; i++) {
            const rgame_vertex *baked = &recording->vertices[batch->first_vertex + i];

            /* Offset first, then the current transform — so the offset is in
             * the recording's own coordinates and the transform is the world's,
             * which is the order a camera needs. */
            rgame_transform_apply(&canvas->transforms, baked->x + dx, baked->y + dy, &out[i].x,
                                  &out[i].y);
            out[i].u = baked->u;
            out[i].v = baked->v;
            for (int c = 0; c < 4; c++) {
                out[i].rgba[c] = modulate(baked->rgba[c], tint[c]);
            }
        }
    }
}

void rgame_canvas_submit(const rgame_canvas *canvas, const rgame_draw_backend *backend) {
    rgame_draw_submit(&canvas->queue, backend, canvas->width, canvas->height);
}

const rgame_draw_queue *rgame_canvas_queue(const rgame_canvas *canvas) {
    return &canvas->queue;
}

int rgame_canvas_depth(const rgame_canvas *canvas) {
    return canvas->push_depth + canvas->unrecorded_pushes;
}
