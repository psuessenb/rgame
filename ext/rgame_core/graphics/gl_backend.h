#ifndef RGAME_GL_BACKEND_H
#define RGAME_GL_BACKEND_H

#include "graphics/backend.h"

/*
 * The real OpenGL implementation of the `rgame_draw_backend` table — layer 3,
 * and the only file in the drawing path that calls `gl*`.
 *
 * Everything above it has already decided what to draw and in what order:
 * primitives.c turned shapes into quads, canvas.c transformed and clipped them,
 * draw_queue.c sorted and batched them. What is left here is issuing the calls,
 * which is why the file is short and why it is verified by looking at the
 * screen (`make run`, `rake spec:core`'s pixel checks) rather than by unit
 * tests — the same calls in the same order are already checked against
 * `test/support/recording_backend.c`.
 *
 * ---------------------------------------------------------------------------
 * Which OpenGL this is
 * ---------------------------------------------------------------------------
 *
 * Fixed-function, compatibility-profile GL 1.1: `glOrtho`, client-side vertex
 * arrays, `glDrawArrays`. No shaders and no extension loader (GLAD/GLEW),
 * because none of it needs one — every function used here is in the 1.1 core
 * that ships with the platform's GL library. Moving to core-profile modern GL
 * would be a deliberate decision with a loader attached; see CLAUDE.md.
 */

typedef struct {
    /* Remembered from begin_frame so set_clip can flip a screen-space rectangle
     * into GL's bottom-up scissor coordinates. */
    int width, height;
} rgame_gl_backend;

/*
 * A backend table driving real GL, over caller-owned state.
 *
 * `state` must outlive the returned table — it is the `ctx` every callback
 * receives. Typically both live in the app.
 */
rgame_draw_backend rgame_gl_backend_table(rgame_gl_backend *state);

#endif /* RGAME_GL_BACKEND_H */
