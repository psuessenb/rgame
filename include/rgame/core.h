#ifndef RGAME_CORE_H
#define RGAME_CORE_H

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Public API of the core engine.
 *
 * This header intentionally exposes no SDL or OpenGL types. Callers (the
 * standalone app in src/main.c today, a Ruby C extension later) only ever
 * see an opaque handle. That keeps the door open for wrapping this library
 * from Ruby without leaking C-library-specific types into ruby.h-using code.
 */

typedef struct rgame_app rgame_app;

/* Creates the window, GL context and internal state. Returns NULL on failure. */
rgame_app *rgame_app_create(int width, int height, const char *title);

/* Destroys the GL context/window and frees the app. Safe to call with NULL. */
void rgame_app_destroy(rgame_app *app);

/*
 * Per-frame callbacks supplied to rgame_app_run.
 *
 * These are deliberately fixed-arity (each takes exactly the arguments it
 * needs, plus an opaque userdata pointer) rather than variadic. A variadic
 * calling convention on a per-frame hot path allocates/marshals on every
 * single call for no benefit — see docs/c_engine_feature_specs.md section 4,
 * which calls this out as a concrete cost worth designing out from the start.
 *
 * `userdata` is passed straight through from rgame_app_run so the callbacks
 * can reach the caller's own state without globals.
 */
typedef void (*rgame_update_fn)(void *userdata, double dt_seconds);
typedef void (*rgame_draw_fn)(void *userdata);
typedef int (*rgame_needs_redraw_fn)(void *userdata);

/*
 * Runs the main loop until the app quits (window closed or Escape pressed).
 *
 * The engine owns the loop and calls back out to the caller:
 *  - `update` runs at a fixed timestep via an internal accumulator, so it may
 *    be called zero or several times per rendered frame; dt_seconds is that
 *    fixed step, not wall-clock frame time. Must not be NULL.
 *  - `draw` renders one frame. Must not be NULL.
 *  - `needs_redraw`, if non-NULL, is polled before drawing; returning 0 skips
 *    the draw for that frame (simulation still advances). Pass NULL to always
 *    redraw.
 *  - `userdata` is forwarded to every callback; may be NULL.
 */
void rgame_app_run(rgame_app *app, rgame_update_fn update, rgame_draw_fn draw,
                   rgame_needs_redraw_fn needs_redraw, void *userdata);

/* Monotonic milliseconds since startup. For time-based animation phase, etc. */
unsigned int rgame_app_ticks_ms(const rgame_app *app);

/* Most recent frames-per-second reading (updated ~once per second). */
double rgame_app_fps(const rgame_app *app);

#ifdef __cplusplus
}
#endif

#endif /* RGAME_CORE_H */
