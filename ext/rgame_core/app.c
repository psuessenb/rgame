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
#include "app_gl.h"
#include "frame_loop.h"
#include "input.h"
#include "gamepad.h"

#include <SDL2/SDL.h>
#include <SDL2/SDL_opengl.h>
#include <stdlib.h>

/* Fixed simulation step and the cap on catch-up steps per rendered frame.
 * 1/60 s tick; at most 5 sim steps before we drop backlog (see frame_loop.h). */
#define RGAME_TICK_SECONDS (1.0 / 60.0)
#define RGAME_MAX_TICKS_PER_FRAME 5

/*
 * How many apps are alive. SDL_Init is safe to call repeatedly, but SDL_Quit
 * is not paired with it — it tears down *everything* regardless of how many
 * callers still need SDL. Destroying one app while another lived therefore
 * pulled the video subsystem out from under it and segfaulted inside GC, which
 * is exactly the shape a spec suite produces (many short-lived Apps, collected
 * at unpredictable times). So SDL is shut down only when the last app goes.
 *
 * Single-threaded by assumption, like the rest of the engine.
 */
static int rgame_live_apps = 0;

struct rgame_app {
    SDL_Window *window;
    SDL_GLContext gl_context;
    int running;
    /*
     * How many things still hold this pointer: the creator, plus every image
     * uploaded into this app's context. The window and context are torn down
     * the moment rgame_app_destroy is called — this refcount only governs when
     * the *struct* is freed, so that an image outliving its app finds a valid
     * pointer saying "the context is gone" rather than freed memory.
     *
     * This matters because Ruby's collector may sweep an app and its images in
     * the same pass, in an order nothing guarantees. Nothing leaks when the app
     * goes first: destroying a GL context frees every texture in it, which is
     * why the image side can simply skip its glDeleteTextures.
     */
    int refs;
    rgame_frame_loop frame_loop;
    rgame_fps_counter fps_counter;
    rgame_input_state input;
    rgame_gamepads gamepads;
};

rgame_app *rgame_app_create(int width, int height, const char *title) {
    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_GAMECONTROLLER) != 0) {
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

    rgame_live_apps++;

    app->running = 1;
    app->refs = 1;
    rgame_input_state_clear(&app->input);
    rgame_gamepads_init(&app->gamepads);
    rgame_frame_loop_init(&app->frame_loop);
    rgame_fps_counter_init(&app->fps_counter);
    return app;
}

/* Frees the struct once nothing points at it any more. The window and context
 * are already gone by this point; see the refs comment above. */
static void app_unref(rgame_app *app) {
    if (--app->refs <= 0) {
        free(app);
    }
}

void rgame_app_destroy(rgame_app *app) {
    if (!app) {
        return;
    }

    /* Idempotent: the window is NULLed below, so a second call falls out here
     * rather than shutting SDL down twice or dropping a reference twice. */
    if (!app->window && !app->gl_context) {
        return;
    }

    rgame_gamepads_shutdown(&app->gamepads);
    if (app->gl_context) {
        SDL_GL_DeleteContext(app->gl_context);
        app->gl_context = NULL;
    }
    if (app->window) {
        SDL_DestroyWindow(app->window);
        app->window = NULL;
    }

    if (--rgame_live_apps <= 0) {
        rgame_live_apps = 0;
        SDL_Quit();
    }

    app_unref(app);
}

void rgame_app_gl_retain(rgame_app *app) {
    if (app) {
        app->refs++;
    }
}

void rgame_app_gl_release(rgame_app *app) {
    if (app) {
        app_unref(app);
    }
}

int rgame_app_gl_make_current(rgame_app *app) {
    /* Both are NULLed by rgame_app_destroy, so this also answers "is there
     * still a context to draw into?" for anything holding a retained app. */
    if (!app || !app->window || !app->gl_context) {
        return 0;
    }
    return SDL_GL_MakeCurrent(app->window, app->gl_context) == 0;
}

/*
 * The button ids in core.h are SDL scancodes, but core.h can't say so in a way
 * the compiler checks — it must not include SDL. These assertions close that
 * gap at compile time, so the two can never drift apart silently.
 */
_Static_assert(RGAME_KEY_RETURN == SDL_SCANCODE_RETURN, "key id must match SDL scancode");
_Static_assert(RGAME_KEY_ESCAPE == SDL_SCANCODE_ESCAPE, "key id must match SDL scancode");
_Static_assert(RGAME_KEY_SPACE == SDL_SCANCODE_SPACE, "key id must match SDL scancode");
_Static_assert(RGAME_KEY_F1 == SDL_SCANCODE_F1, "key id must match SDL scancode");
_Static_assert(RGAME_KEY_RIGHT == SDL_SCANCODE_RIGHT, "key id must match SDL scancode");
_Static_assert(RGAME_KEY_LEFT == SDL_SCANCODE_LEFT, "key id must match SDL scancode");
_Static_assert(RGAME_KEY_DOWN == SDL_SCANCODE_DOWN, "key id must match SDL scancode");
_Static_assert(RGAME_KEY_UP == SDL_SCANCODE_UP, "key id must match SDL scancode");

/* The snapshot array must be exactly as long as SDL's keyboard state array,
 * since filling it is a straight copy. */
_Static_assert(RGAME_KEYBOARD_KEY_COUNT == SDL_NUM_SCANCODES,
               "RGAME_KEYBOARD_KEY_COUNT must match SDL_NUM_SCANCODES");

/* Every keyboard id must land inside the keyboard range of the flat id space,
 * or rgame_input_state_down would reject it as belonging to another device. */
_Static_assert(SDL_NUM_SCANCODES - 1 <= RGAME_BUTTON_KEYBOARD_LAST,
               "SDL scancodes must fit the keyboard button-id range");

/*
 * Copies SDL's live keyboard state into the app's snapshot. Called once per
 * frame, right after the event queue is drained, so every simulation tick in
 * that frame sees identical input — see input.h for why that matters.
 *
 * SDL_GetKeyboardState returns a pointer to SDL's own internal array, which
 * SDL updates as events are pumped; it must not be freed, and holding onto it
 * across frames would defeat the whole point, so it is copied here and then
 * forgotten.
 */
static void rgame_app_snapshot_input(rgame_app *app) {
    int count = 0;
    const Uint8 *keys = SDL_GetKeyboardState(&count);
    if (keys && count == RGAME_KEYBOARD_KEY_COUNT) {
        rgame_input_state_set_keys(&app->input, keys);
    }
    rgame_gamepads_snapshot(&app->gamepads, &app->input);
}

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
        case SDL_CONTROLLERDEVICEADDED: {
            /* For ADDED, `which` is a device *index*. */
            int slot = rgame_gamepads_add(&app->gamepads, event.cdevice.which);
            if (slot != RGAME_DEVICE_SLOT_NONE && cb->gamepad_connected) {
                cb->gamepad_connected(cb->userdata, slot);
            }
            break;
        }
        case SDL_CONTROLLERDEVICEREMOVED: {
            /* ...but for REMOVED, the same field is an *instance id*. Passing
             * one where the other is expected is silent and wrong. */
            int slot = rgame_gamepads_remove(&app->gamepads, event.cdevice.which);
            if (slot != RGAME_DEVICE_SLOT_NONE) {
                /* Drop any buttons that were held at the moment it vanished. */
                rgame_input_state_clear_pad(&app->input, slot);
                if (cb->gamepad_disconnected) {
                    cb->gamepad_disconnected(cb->userdata, slot);
                }
            }
            break;
        }
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

        /* One sample per frame, after the events that produced it. */
        rgame_app_snapshot_input(app);

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

int rgame_app_input_down(const rgame_app *app, int device, int button_id) {
    return rgame_input_state_down(&app->input, device, button_id);
}

float rgame_app_input_axis(const rgame_app *app, int device, int axis_id) {
    return rgame_input_state_axis(&app->input, device, axis_id);
}

int rgame_app_gamepad_connected(const rgame_app *app, int slot) {
    return rgame_gamepads_connected(&app->gamepads, slot);
}

const char *rgame_app_gamepad_name(const rgame_app *app, int slot) {
    return rgame_gamepads_name(&app->gamepads, slot);
}

int rgame_app_gamepad_count(const rgame_app *app) {
    return rgame_gamepads_count(&app->gamepads);
}

unsigned int rgame_app_ticks_ms(const rgame_app *app) {
    (void)app; /* SDL's clock is global; app is taken for API consistency. */
    return SDL_GetTicks();
}

double rgame_app_fps(const rgame_app *app) {
    return app->fps_counter.fps;
}
