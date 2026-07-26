/*
 * app.c — the engine itself: SDL window + OpenGL context, and the main loop.
 *
 * This is the implementation behind the opaque `rgame_app` handle declared in
 * include/rgame/core.h. It owns the loop and calls back out to the caller's
 * update/draw functions, which is what lets the same engine be driven from a C
 * main() (src/main.c) and from Ruby (core_ext.c) without either of them
 * knowing about SDL or GL.
 *
 * Three files in this directory have "core"-ish names and it's worth being
 * clear which is which:
 *
 *   include/rgame/core.h  the public API — no SDL/GL types, safe to include
 *                         anywhere (this file implements it)
 *   app.c                 this file: the real SDL/GL engine behind that API
 *   core_ext.c            the Ruby binding, which only ever calls core.h
 *
 * The pure timing logic (accumulator, FPS counter) deliberately lives in
 * frame_loop.{c,h} instead of here, so it can be unit-tested without a window.
 */

#include "rgame/core.h"
#include "frame_loop.h"

#include <SDL2/SDL.h>
#include <SDL2/SDL_opengl.h>
#include <stdlib.h>

/* Fixed simulation step and the cap on catch-up steps per rendered frame.
 * 1/60 s tick; at most 5 sim steps before we drop backlog (see frame_loop.h). */
#define RGAME_TICK_SECONDS (1.0 / 60.0)
#define RGAME_MAX_TICKS_PER_FRAME 5

struct rgame_app {
    SDL_Window *window;
    SDL_GLContext gl_context;
    int running;
    rgame_frame_loop frame_loop;
    rgame_fps_counter fps_counter;
};

rgame_app *rgame_app_create(int width, int height, const char *title) {
    if (SDL_Init(SDL_INIT_VIDEO) != 0) {
        SDL_Log("SDL_Init failed: %s", SDL_GetError());
        return NULL;
    }

    SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
    SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 24);

    rgame_app *app = calloc(1, sizeof(rgame_app));
    if (!app) {
        SDL_Quit();
        return NULL;
    }

    app->window = SDL_CreateWindow(
        title,
        SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
        width, height,
        SDL_WINDOW_OPENGL | SDL_WINDOW_SHOWN);
    if (!app->window) {
        SDL_Log("SDL_CreateWindow failed: %s", SDL_GetError());
        free(app);
        SDL_Quit();
        return NULL;
    }

    app->gl_context = SDL_GL_CreateContext(app->window);
    if (!app->gl_context) {
        SDL_Log("SDL_GL_CreateContext failed: %s", SDL_GetError());
        SDL_DestroyWindow(app->window);
        free(app);
        SDL_Quit();
        return NULL;
    }

    SDL_GL_SetSwapInterval(1); /* vsync */
    glEnable(GL_DEPTH_TEST);

    app->running = 1;
    rgame_frame_loop_init(&app->frame_loop);
    rgame_fps_counter_init(&app->fps_counter);
    return app;
}

void rgame_app_destroy(rgame_app *app) {
    if (!app) {
        return;
    }
    if (app->gl_context) {
        SDL_GL_DeleteContext(app->gl_context);
    }
    if (app->window) {
        SDL_DestroyWindow(app->window);
    }
    free(app);
    SDL_Quit();
}

/*
 * The button ids in core.h are SDL scancodes, but core.h can't say so in a way
 * the compiler checks — it must not include SDL. These assertions close that
 * gap at compile time, so the two can never drift apart silently.
 */
_Static_assert(RGAME_KEY_ESCAPE == SDL_SCANCODE_ESCAPE,
               "RGAME_KEY_ESCAPE must match SDL_SCANCODE_ESCAPE");
_Static_assert(RGAME_KEY_F1 == SDL_SCANCODE_F1,
               "RGAME_KEY_F1 must match SDL_SCANCODE_F1");

/*
 * Drains the SDL event queue, dispatching to the caller's event callbacks.
 *
 * Closing the window still stops the loop here — that really is the platform's
 * decision. Quitting on a *key*, though, is a game decision and deliberately
 * isn't handled: the caller gets the button_down and closes if it wants to.
 */
static void rgame_app_poll_events(rgame_app *app, const rgame_app_callbacks *cb) {
    SDL_Event event;
    while (SDL_PollEvent(&event)) {
        switch (event.type) {
        case SDL_QUIT:
            app->running = 0;
            break;
        case SDL_KEYDOWN:
            /* event.key.repeat is non-zero for auto-repeats while a key is
             * held. A discrete press must fire exactly once, so drop those. */
            if (!event.key.repeat && cb->button_down) {
                cb->button_down(cb->userdata, (int)event.key.keysym.scancode);
            }
            break;
        case SDL_KEYUP:
            if (cb->button_up) {
                cb->button_up(cb->userdata, (int)event.key.keysym.scancode);
            }
            break;
        case SDL_WINDOWEVENT:
            if (event.window.event == SDL_WINDOWEVENT_RESIZED) {
                glViewport(0, 0, event.window.data1, event.window.data2);
                if (cb->resize) {
                    cb->resize(cb->userdata, event.window.data1, event.window.data2);
                }
            }
            break;
        default:
            break;
        }
    }
}

void rgame_app_run(rgame_app *app, const rgame_app_callbacks *cb) {
    if (!app || !cb) {
        return;
    }

    Uint32 prev_ms = SDL_GetTicks();

    /* Every step re-checks `running`, because any callback may have asked to
     * close — including a Ruby callback that raised and unwound into one. */
    while (app->running) {
        rgame_app_poll_events(app, cb);
        if (!app->running) {
            break;
        }

        Uint32 now_ms = SDL_GetTicks();
        double elapsed_seconds = (now_ms - prev_ms) / 1000.0;
        prev_ms = now_ms;

        /* Once per frame, before the tick batch: the caller's chance to sample
         * input once and reuse it across every catch-up tick below. */
        if (cb->frame_begin) {
            cb->frame_begin(cb->userdata);
        }
        if (!app->running) {
            break;
        }

        /* Fixed-timestep simulation: run whole ticks the accumulator has banked. */
        int ticks = rgame_frame_loop_advance(&app->frame_loop, elapsed_seconds,
                                             RGAME_TICK_SECONDS, RGAME_MAX_TICKS_PER_FRAME);
        for (int i = 0; i < ticks && app->running; i++) {
            if (cb->update) {
                cb->update(cb->userdata, RGAME_TICK_SECONDS);
            }
        }
        if (!app->running) {
            break;
        }

        /* Count every loop iteration toward FPS. With the current always-draw
         * behavior this equals the render rate; if needs_redraw skipping is
         * added later, revisit whether FPS should track loop vs. render rate. */
        rgame_fps_counter_tick(&app->fps_counter, elapsed_seconds);

        int redraw = cb->needs_redraw ? cb->needs_redraw(cb->userdata) : 1;
        if (!app->running) {
            break;
        }

        if (redraw) {
            glClearColor(0.1f, 0.1f, 0.15f, 1.0f);
            glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
            if (cb->draw) {
                cb->draw(cb->userdata);
            }
            SDL_GL_SwapWindow(app->window);
        }
    }
}

void rgame_app_close(rgame_app *app) {
    if (app) {
        app->running = 0;
    }
}

int rgame_app_width(const rgame_app *app) {
    int width = 0;
    SDL_GetWindowSize(app->window, &width, NULL);
    return width;
}

int rgame_app_height(const rgame_app *app) {
    int height = 0;
    SDL_GetWindowSize(app->window, NULL, &height);
    return height;
}

const char *rgame_app_title(const rgame_app *app) {
    return SDL_GetWindowTitle(app->window);
}

void rgame_app_set_title(rgame_app *app, const char *title) {
    SDL_SetWindowTitle(app->window, title);
}

unsigned int rgame_app_ticks_ms(const rgame_app *app) {
    (void)app; /* SDL's clock is global; app is taken for API consistency. */
    return SDL_GetTicks();
}

double rgame_app_fps(const rgame_app *app) {
    return app->fps_counter.fps;
}
