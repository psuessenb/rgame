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
#include "app/app_gl.h"
#include "graphics/canvas.h"
#include "text/font_internal.h"
#include "app/frame_loop.h"
#include "input/gamepad.h"
#include "graphics/gl_backend.h"
#include "graphics/image_internal.h"
#include "input/input.h"
#include "graphics/primitives.h"
#include "graphics/recording.h"

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

    /* The drawing surface, and the GL backend it is submitted to. Both live
     * for the app's lifetime; the canvas reuses its buffers across frames
     * rather than reallocating (see draw_queue.h). */
    rgame_canvas canvas;
    rgame_gl_backend gl;

    /*
     * Where draws go while a recording is open. Kept for the app's lifetime
     * like the frame canvas, so baking a layer between levels does not
     * allocate a queue from scratch each time.
     */
    rgame_canvas record_canvas;
    int recording;
    /*
     * Whether a frame is currently open. Drawing outside `draw` would append to
     * a queue that is about to be reset — silently drawing nothing — so every
     * primitive checks this, and the Ruby binding turns it into an error.
     */
    int drawing;
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

    rgame_live_apps++;

    app->running = 1;
    app->refs = 1;
    app->drawing = 0;
    app->recording = 0;
    rgame_canvas_init(&app->canvas);
    rgame_canvas_init(&app->record_canvas);
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
    rgame_canvas_destroy(&app->canvas);
    rgame_canvas_destroy(&app->record_canvas);
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

int rgame_app_gl_make_current(rgame_app *app, rgame_gl_context_save *saved) {
    if (saved) {
        /* Captured before the switch, and captured even if the switch then
         * fails — restoring a no-op is free, and forgetting to capture is not
         * recoverable. */
        saved->window = SDL_GL_GetCurrentWindow();
        saved->context = SDL_GL_GetCurrentContext();
    }

    /* Both are NULLed by rgame_app_destroy, so this also answers "is there
     * still a context to draw into?" for anything holding a retained app. */
    if (!app || !app->window || !app->gl_context) {
        return 0;
    }
    return SDL_GL_MakeCurrent(app->window, app->gl_context) == 0;
}

void rgame_app_gl_restore(const rgame_gl_context_save *saved) {
    if (saved && saved->context) {
        SDL_GL_MakeCurrent((SDL_Window *)saved->window, (SDL_GLContext)saved->context);
    }
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
                /* The viewport is set from the current size every frame, in the
                 * backend's begin_frame, so there is nothing to update here. */
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
            /*
             * Open the frame, let the caller draw into it, then sort, batch and
             * submit. Re-stating the window size every frame is also how a
             * resize takes effect, so there is no separate path to forget.
             *
             * The caller's draw callback only ever appends to the queue; the
             * bracketing is the engine's job. That is deliberate — a hook the
             * user must remember to open and close is a hook someone forgets.
             */
            rgame_canvas_begin_frame(&app->canvas, rgame_app_width(app), rgame_app_height(app));
            app->drawing = 1;
            if (cb->draw) {
                cb->draw(cb->userdata);
            }
            app->drawing = 0;
            rgame_canvas_end_frame(&app->canvas);

            rgame_draw_backend backend = rgame_gl_backend_table(&app->gl);
            rgame_canvas_submit(&app->canvas, &backend);
            SDL_GL_SwapWindow(app->window);
        }
    }
}

/* ------------------------------------------------------------------------- *
 * Drawing
 *
 * Each of these is a guard plus one call into primitives.c, which is pure and
 * Check-tested. The guard is the interesting part: outside a frame the canvas
 * would happily accept the vertices and throw them away at the next
 * begin_frame, so refusing here is what turns "my draw call does nothing" into
 * something a caller can be told about.
 * ------------------------------------------------------------------------- */

int rgame_app_is_drawing(const rgame_app *app) {
    return app && app->drawing;
}

/*
 * The canvas to draw into, or NULL if no frame is open.
 *
 * While a recording is open this is the recording's own canvas, which is the
 * entire mechanism: every draw function below is unchanged, and capture is a
 * matter of where their vertices land.
 */
static rgame_canvas *drawing_canvas(rgame_app *app) {
    if (!rgame_app_is_drawing(app)) {
        return NULL;
    }
    return app->recording ? &app->record_canvas : &app->canvas;
}

void rgame_app_draw_rect(rgame_app *app, float x, float y, float width, float height,
                         unsigned int color, double z) {
    rgame_canvas *canvas = drawing_canvas(app);
    if (canvas) {
        rgame_prim_rect(canvas, x, y, width, height, color, z);
    }
}

void rgame_app_draw_quad(rgame_app *app, const float *xy8, unsigned int color, double z) {
    rgame_canvas *canvas = drawing_canvas(app);
    if (canvas && xy8) {
        rgame_canvas_quad(canvas, xy8, color, z);
    }
}

void rgame_app_draw_triangle(rgame_app *app, const float *xy6, unsigned int color, double z) {
    rgame_canvas *canvas = drawing_canvas(app);
    if (canvas && xy6) {
        rgame_canvas_triangle(canvas, xy6, color, z);
    }
}

void rgame_app_draw_line(rgame_app *app, float x1, float y1, float x2, float y2,
                         float thickness, unsigned int color, double z) {
    rgame_canvas *canvas = drawing_canvas(app);
    if (canvas) {
        rgame_prim_line(canvas, x1, y1, x2, y2, thickness, color, z);
    }
}

void rgame_app_draw_circle(rgame_app *app, float cx, float cy, float radius, int segments,
                           unsigned int color, double z) {
    rgame_canvas *canvas = drawing_canvas(app);
    if (canvas) {
        rgame_prim_circle(canvas, cx, cy, radius, segments, color, z);
    }
}

/* An image may only be drawn by the app that uploaded it; see core.h. A NULL
 * image is "nothing to draw", not a mismatch, and simply draws nothing. */
static int image_belongs_here(const rgame_app *app, const rgame_image *image) {
    return !image || rgame_image_owner(image) == app;
}

int rgame_app_draw_image(rgame_app *app, const rgame_image *image, float x, float y,
                         unsigned int color, double z) {
    if (!image_belongs_here(app, image)) {
        return 0;
    }

    rgame_canvas *canvas = drawing_canvas(app);
    if (canvas) {
        rgame_prim_image(canvas, rgame_image_view(image), x, y, color, z);
    }
    return 1;
}

int rgame_app_draw_image_scaled(rgame_app *app, const rgame_image *image, float x, float y,
                                float scale_x, float scale_y, unsigned int color, double z) {
    if (!image_belongs_here(app, image)) {
        return 0;
    }

    rgame_canvas *canvas = drawing_canvas(app);
    if (canvas) {
        rgame_prim_image_scaled(canvas, rgame_image_view(image), x, y, scale_x, scale_y, color, z);
    }
    return 1;
}

int rgame_app_draw_image_rot(rgame_app *app, const rgame_image *image, float cx, float cy,
                             float angle_degrees, float scale, unsigned int color, double z) {
    if (!image_belongs_here(app, image)) {
        return 0;
    }

    rgame_canvas *canvas = drawing_canvas(app);
    if (canvas) {
        rgame_prim_image_rot(canvas, rgame_image_view(image), cx, cy, angle_degrees, scale, color,
                             z);
    }
    return 1;
}

/* A font's atlas pages live in one GL context, exactly like an image's
 * texture; see image_belongs_here. */
static int font_belongs_here(const rgame_app *app, const rgame_font *font) {
    return !font || rgame_font_owner(font) == app;
}

int rgame_app_draw_text(rgame_app *app, rgame_font *font, const char *text, size_t length,
                        float x, float y, unsigned int color, double z) {
    if (!font_belongs_here(app, font)) {
        return 0;
    }

    rgame_canvas *canvas = drawing_canvas(app);
    if (!canvas || !font || !text) {
        return 1;
    }

    /*
     * The same cursor `rgame_font_measure` uses — not the same arithmetic, the
     * same code. Two loops that both sum advances drift the moment one gains a
     * rounding rule, and then every centred label in the game sits a pixel off
     * with nothing to point at.
     */
    rgame_text_cursor cursor;
    rgame_text_cursor_init(&cursor, text, length);

    int codepoint = 0;
    float pen_x = 0.0f;
    while (rgame_text_cursor_next(&cursor, rgame_font_typeface(font), &codepoint, &pen_x)) {
        rgame_glyph glyph;
        unsigned int texture = 0;
        int page_width = 0, page_height = 0;
        if (!rgame_font_glyph(font, codepoint, &glyph, &texture, &page_width, &page_height)) {
            continue; /* skip the one glyph, draw the rest of the string */
        }

        /* The bearings turn a pen position into where the ink goes: x from the
         * pen, y from the top of the line box. A space has no rect and
         * rgame_prim_glyph draws nothing for it. */
        rgame_prim_glyph(canvas, texture, glyph.rect, page_width, page_height,
                         x + pen_x + glyph.bearing_x, y + glyph.bearing_y, color, z);
    }

    return 1;
}

void rgame_app_push_translate(rgame_app *app, float dx, float dy) {
    rgame_canvas *canvas = drawing_canvas(app);
    if (canvas) {
        rgame_canvas_push_translate(canvas, dx, dy);
    }
}

void rgame_app_push_rotate(rgame_app *app, float degrees, float pivot_x, float pivot_y) {
    rgame_canvas *canvas = drawing_canvas(app);
    if (canvas) {
        rgame_canvas_push_rotate(canvas, degrees, pivot_x, pivot_y);
    }
}

void rgame_app_push_scale(rgame_app *app, float sx, float sy) {
    rgame_canvas *canvas = drawing_canvas(app);
    if (canvas) {
        rgame_canvas_push_scale(canvas, sx, sy);
    }
}

int rgame_app_push_clip(rgame_app *app, int x, int y, int width, int height) {
    /* A clip cannot be baked: see the recording section of core.h. Refusing
     * keeps the push/pop pairing honest — nothing was pushed, so the caller's
     * matching pop has nothing to undo either. */
    if (app && app->recording) {
        return 0;
    }

    rgame_canvas *canvas = drawing_canvas(app);
    if (canvas) {
        rgame_canvas_push_clip(canvas, rgame_rect_make(x, y, width, height));
    }
    return 1;
}

void rgame_app_pop(rgame_app *app) {
    rgame_canvas *canvas = drawing_canvas(app);
    if (canvas) {
        rgame_canvas_pop(canvas);
    }
}

/* ------------------------------------------------------------------------- *
 * Recordings
 * ------------------------------------------------------------------------- */

int rgame_app_begin_record(rgame_app *app) {
    if (!rgame_app_is_drawing(app) || app->recording) {
        return 0;
    }

    /* The size only decides the recording canvas's base clip. Nothing inside
     * may narrow it and the recorded clips are discarded at capture, so it
     * simply has to be big enough not to drop anything — the window is. */
    rgame_canvas_begin_frame(&app->record_canvas, rgame_app_width(app), rgame_app_height(app));
    app->recording = 1;
    return 1;
}

rgame_recording *rgame_app_end_record(rgame_app *app) {
    if (!app || !app->recording) {
        return NULL;
    }
    app->recording = 0;

    /* Sorting and grouping is exactly the work a recording exists to do once,
     * so it happens here rather than on every replay. */
    rgame_canvas_end_frame(&app->record_canvas);

    rgame_recording *recording = calloc(1, sizeof(rgame_recording));
    if (!recording) {
        return NULL;
    }
    if (!rgame_recording_capture(recording, rgame_canvas_queue(&app->record_canvas))) {
        free(recording);
        return NULL;
    }
    return recording;
}

void rgame_app_cancel_record(rgame_app *app) {
    if (app) {
        app->recording = 0;
    }
}

void rgame_recording_free(rgame_recording *recording) {
    if (recording) {
        rgame_recording_destroy(recording);
        free(recording);
    }
}

void rgame_app_draw_recording(rgame_app *app, const rgame_recording *recording, float x,
                              float y, unsigned int color, double z) {
    rgame_canvas *canvas = drawing_canvas(app);
    if (canvas) {
        rgame_canvas_replay(canvas, recording, x, y, color, z);
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
