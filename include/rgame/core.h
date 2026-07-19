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

/* Pumps the SDL event queue. Returns 0 once the app should quit, non-zero otherwise. */
int rgame_app_poll_events(rgame_app *app);

/* Advances animation/simulation state by dt_seconds. */
void rgame_app_update(rgame_app *app, double dt_seconds);

/* Draws one frame and swaps buffers. */
void rgame_app_render(rgame_app *app);

#ifdef __cplusplus
}
#endif

#endif /* RGAME_CORE_H */
