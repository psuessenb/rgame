#include <stdio.h>

#include "rgame/core.h"

/*
 * Standalone entry point. Its whole job is to create the app, hand the engine
 * per-frame callbacks, and clean up — the loop and timing live in the engine
 * (ext/rgame_core/app.c). The Ruby extension drives the same rgame_app_run
 * seam, just with Ruby-side callbacks instead of these.
 *
 * The update/draw callbacks are intentionally empty for now: there are no draw
 * primitives yet (see docs/c_engine_feature_specs.md section 2), so the window
 * just shows the engine's clear color. They fill in as those primitives land.
 *
 * Escape-to-quit is handled here rather than in the engine, because "which key
 * quits" is a game decision. This is the C mirror of what a Ruby subclass does
 * in its own button_down.
 */

static void on_update(void *userdata, double dt_seconds) {
    (void)userdata;
    (void)dt_seconds;
}

static void on_draw(void *userdata) {
    (void)userdata;
}

static void on_button_down(void *userdata, int button_id) {
    if (button_id == RGAME_KEY_ESCAPE) {
        rgame_app_close((rgame_app *)userdata);
    }
}

int main(void) {
    rgame_app *app = rgame_app_create(800, 600, "rgame - SDL + OpenGL");
    if (!app) {
        fprintf(stderr, "Failed to create app\n");
        return 1;
    }

    /* Unset callbacks are simply skipped, so only the hooks actually used need
     * naming. `userdata` is the app itself, which is what on_button_down closes. */
    rgame_app_callbacks callbacks = {
        .update = on_update,
        .draw = on_draw,
        .button_down = on_button_down,
        .userdata = app,
    };

    rgame_app_run(app, &callbacks);

    rgame_app_destroy(app);
    return 0;
}
