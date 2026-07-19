#ifndef CTEST_CORE_H
#define CTEST_CORE_H

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

typedef struct ctest_app ctest_app;

/* Creates the window, GL context and internal state. Returns NULL on failure. */
ctest_app *ctest_app_create(int width, int height, const char *title);

/* Destroys the GL context/window and frees the app. Safe to call with NULL. */
void ctest_app_destroy(ctest_app *app);

/* Pumps the SDL event queue. Returns 0 once the app should quit, non-zero otherwise. */
int ctest_app_poll_events(ctest_app *app);

/* Advances animation/simulation state by dt_seconds. */
void ctest_app_update(ctest_app *app, double dt_seconds);

/* Draws one frame and swaps buffers. */
void ctest_app_render(ctest_app *app);

#ifdef __cplusplus
}
#endif

#endif /* CTEST_CORE_H */
