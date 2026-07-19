#include <stdio.h>

#include "rgame/core.h"

/*
 * Standalone entry point. Its whole job is to create the app, hand the engine
 * per-frame callbacks, and clean up — the loop and timing live in the engine
 * (src/core.c). A future Ruby extension drives the same rgame_app_run seam,
 * just with Ruby-side callbacks instead of these.
 *
 * The callbacks are intentionally empty for now: there are no draw primitives
 * yet (see docs/c_engine_feature_specs.md section 2), so the window just shows
 * the engine's clear color. update/draw fill in as those primitives land.
 */

static void on_update(void *userdata, double dt_seconds) {
    (void)userdata;
    (void)dt_seconds;
}

static void on_draw(void *userdata) {
    (void)userdata;
}

int main(void) {
    rgame_app *app = rgame_app_create(800, 600, "rgame - SDL + OpenGL");
    if (!app) {
        fprintf(stderr, "Failed to create app\n");
        return 1;
    }

    /* NULL needs_redraw = redraw every frame. */
    rgame_app_run(app, on_update, on_draw, NULL, NULL);

    rgame_app_destroy(app);
    return 0;
}
