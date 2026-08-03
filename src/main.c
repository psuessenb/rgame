#include <stdio.h>

#include "rgame/core.h"

/*
 * Standalone entry point. Its whole job is to create the app, hand the engine
 * per-frame callbacks, and clean up — the loop and timing live in the engine
 * (ext/rgame_core/app.c). The Ruby extension drives the same rgame_app_run
 * seam, just with Ruby-side callbacks instead of these.
 *
 * What it draws is a smoke test for the drawing API, not a game: one of each
 * primitive, a rotating shape to show the transform stack turning, and a
 * clipped region. Looking at it is the only check on layer 3 that a person can
 * make — everything under it is covered by `make test` and `rake spec:core`.
 *
 * Escape-to-quit is handled here rather than in the engine, because "which key
 * quits" is a game decision. This is the C mirror of what a Ruby subclass does
 * in its own button_down.
 */

/* Turned a little further every tick, so a stuck frame is obvious. */
static float spin_degrees = 0.0f;

static void on_update(void *userdata, double dt_seconds) {
    (void)userdata;
    spin_degrees += (float)(dt_seconds * 45.0);
}

/* Colours are packed 0xRRGGBBAA, the same form RGame::Util::Color hands over. */
#define COLOR_RED 0xE04040FFu
#define COLOR_GREEN 0x40E060FFu
#define COLOR_BLUE 0x4060E0FFu
#define COLOR_YELLOW 0xE0C040FFu
#define COLOR_TRANSLUCENT_WHITE 0xFFFFFF80u

static void on_draw(void *userdata) {
    rgame_app *app = userdata;

    rgame_app_draw_rect(app, 40.0f, 40.0f, 160.0f, 100.0f, COLOR_RED, 0.0);

    /* Higher z wins wherever they overlap, whatever order the calls came in. */
    rgame_app_draw_rect(app, 120.0f, 90.0f, 160.0f, 100.0f, COLOR_TRANSLUCENT_WHITE, 1.0);

    float triangle[6] = { 400.0f, 40.0f, 480.0f, 180.0f, 320.0f, 180.0f };
    rgame_app_draw_triangle(app, triangle, COLOR_GREEN, 0.0);

    rgame_app_draw_circle(app, 620.0f, 110.0f, 70.0f, 64, COLOR_BLUE, 0.0);
    rgame_app_draw_line(app, 40.0f, 240.0f, 760.0f, 240.0f, 6.0f, COLOR_YELLOW, 0.0);

    /* The transform stack: a square turning about its own centre. */
    rgame_app_push_rotate(app, spin_degrees, 400.0f, 380.0f);
    rgame_app_draw_rect(app, 340.0f, 320.0f, 120.0f, 120.0f, COLOR_GREEN, 0.0);
    rgame_app_pop(app);

    /* And the clip stack: the rectangle is twice the size of what shows. */
    rgame_app_push_clip(app, 60, 480, 200, 80);
    rgame_app_draw_rect(app, 60.0f, 440.0f, 400.0f, 160.0f, COLOR_RED, 0.0);
    rgame_app_pop(app);
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
