/*
 * gl_backend.c — the real GL calls. See gl_backend.h for what this is and
 * which OpenGL it targets.
 */

#include "gl_backend.h"

#include <SDL2/SDL_opengl.h>

/* The colour an un-drawn pixel ends up. Not configurable yet — when a game
 * needs its own background it should become an app-level setting rather than a
 * constant here. */
#define RGAME_CLEAR_R 0.1f
#define RGAME_CLEAR_G 0.1f
#define RGAME_CLEAR_B 0.15f

static void gl_begin_frame(void *ctx, int width, int height) {
    rgame_gl_backend *state = ctx;
    state->width = width;
    state->height = height;

    glViewport(0, 0, width, height);

    /*
     * Screen coordinates, not GL's. glOrtho's near/far arguments are given as
     * (left, right, bottom, top): passing height as *bottom* and 0 as *top*
     * flips the y axis, so (0,0) is the top-left corner and y grows downwards —
     * the convention every coordinate in this engine already uses.
     */
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glOrtho(0.0, (double)width, (double)height, 0.0, -1.0, 1.0);
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();

    /*
     * No depth testing. The draw queue has already sorted by z on the CPU, and
     * that is not an optimisation to undo: depth testing and alpha blending do
     * not mix. A translucent pixel that passes the depth test writes depth, so
     * whatever should have shown through it is discarded — which is why
     * translucent UI over gameplay needs a painter's-algorithm sort instead.
     */
    glDisable(GL_DEPTH_TEST);

    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    /* Clear before the scissor test goes on: glClear obeys the scissor, so
     * clearing afterwards would only clear whatever region was last set. */
    glDisable(GL_SCISSOR_TEST);
    glClearColor(RGAME_CLEAR_R, RGAME_CLEAR_G, RGAME_CLEAR_B, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);
    glEnable(GL_SCISSOR_TEST);

    /* Client-side vertex arrays: the vertex data stays in our own buffer and GL
     * reads it at draw time. Switching these on once per frame rather than once
     * per batch is the whole reason they are here and not in draw_batch. */
    glEnableClientState(GL_VERTEX_ARRAY);
    glEnableClientState(GL_TEXTURE_COORD_ARRAY);
    glEnableClientState(GL_COLOR_ARRAY);
}

static void gl_set_clip(void *ctx, rgame_rect clip) {
    rgame_gl_backend *state = ctx;

    /*
     * GL measures the scissor box from the *bottom* of the window; every
     * rectangle in this engine is measured from the top. Flipping it is one
     * line and getting it wrong puts the clip in the mirror-image place, which
     * on a centred test rectangle looks correct.
     */
    glScissor(clip.x, state->height - (clip.y + clip.h), clip.w, clip.h);
}

static void gl_draw_batch(void *ctx, unsigned int texture, const rgame_vertex *vertices,
                          unsigned int count) {
    (void)ctx;

    if (texture == 0) {
        /* Untextured: the colour array alone decides the pixel. */
        glDisable(GL_TEXTURE_2D);
    } else {
        glEnable(GL_TEXTURE_2D);
        glBindTexture(GL_TEXTURE_2D, texture);
    }

    /*
     * The three arrays are interleaved in one `rgame_vertex`, so all three
     * pointers walk the same buffer with the same stride at different offsets.
     * One allocation per frame, one pass over it per batch.
     */
    glVertexPointer(2, GL_FLOAT, sizeof(rgame_vertex), &vertices[0].x);
    glTexCoordPointer(2, GL_FLOAT, sizeof(rgame_vertex), &vertices[0].u);
    glColorPointer(4, GL_UNSIGNED_BYTE, sizeof(rgame_vertex), vertices[0].rgba);

    /* Everything is triangles by the time it reaches here — quads were split
     * upstream, so there is one primitive type to issue. */
    glDrawArrays(GL_TRIANGLES, 0, (GLsizei)count);
}

static void gl_end_frame(void *ctx) {
    (void)ctx;

    /* Leave GL as it was found. The window's own buffer swap is the app's job,
     * not the backend's — the backend has no window. */
    glDisableClientState(GL_VERTEX_ARRAY);
    glDisableClientState(GL_TEXTURE_COORD_ARRAY);
    glDisableClientState(GL_COLOR_ARRAY);
    glDisable(GL_SCISSOR_TEST);
    glDisable(GL_TEXTURE_2D);
}

rgame_draw_backend rgame_gl_backend_table(rgame_gl_backend *state) {
    rgame_draw_backend backend = {
        .begin_frame = gl_begin_frame,
        .set_clip = gl_set_clip,
        .draw_batch = gl_draw_batch,
        .end_frame = gl_end_frame,
        .ctx = state,
    };
    return backend;
}
