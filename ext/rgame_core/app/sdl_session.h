#ifndef RGAME_SDL_SESSION_H
#define RGAME_SDL_SESSION_H

/*
 * Which run of SDL is current. app.c starts SDL when the first app opens and
 * shuts it down when the last one goes, and SDL_Quit frees every handle SDL
 * gave out. A handle that can outlive every app — a virtual gamepad — records
 * the session it was made in and compares, rather than handing SDL a pointer
 * SDL has already freed.
 *
 * Private to the engine, like app_gl.h.
 */

/* Non-zero while SDL is running, and different for every run; 0 when no app is
 * alive. */
unsigned rgame_sdl_session(void);

#endif /* RGAME_SDL_SESSION_H */
