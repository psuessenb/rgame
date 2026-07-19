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

/* Drains the SDL event queue, updating app->running. Internal to the loop. */
static void rgame_app_poll_events(rgame_app *app) {
    SDL_Event event;
    while (SDL_PollEvent(&event)) {
        if (event.type == SDL_QUIT) {
            app->running = 0;
        }
        if (event.type == SDL_KEYDOWN && event.key.keysym.sym == SDLK_ESCAPE) {
            app->running = 0;
        }
        if (event.type == SDL_WINDOWEVENT && event.window.event == SDL_WINDOWEVENT_RESIZED) {
            glViewport(0, 0, event.window.data1, event.window.data2);
        }
    }
}

void rgame_app_run(rgame_app *app, rgame_update_fn update, rgame_draw_fn draw,
                   rgame_needs_redraw_fn needs_redraw, void *userdata) {
    Uint32 prev_ms = SDL_GetTicks();

    while (app->running) {
        rgame_app_poll_events(app);
        if (!app->running) {
            break;
        }

        Uint32 now_ms = SDL_GetTicks();
        double elapsed_seconds = (now_ms - prev_ms) / 1000.0;
        prev_ms = now_ms;

        /* Fixed-timestep simulation: run whole ticks the accumulator has banked. */
        int ticks = rgame_frame_loop_advance(&app->frame_loop, elapsed_seconds,
                                             RGAME_TICK_SECONDS, RGAME_MAX_TICKS_PER_FRAME);
        for (int i = 0; i < ticks; i++) {
            update(userdata, RGAME_TICK_SECONDS);
        }

        /* Count every loop iteration toward FPS. With the current always-draw
         * behavior this equals the render rate; if needs_redraw skipping is
         * added later, revisit whether FPS should track loop vs. render rate. */
        rgame_fps_counter_tick(&app->fps_counter, elapsed_seconds);

        if (!needs_redraw || needs_redraw(userdata)) {
            glClearColor(0.1f, 0.1f, 0.15f, 1.0f);
            glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
            draw(userdata);
            SDL_GL_SwapWindow(app->window);
        }
    }
}

unsigned int rgame_app_ticks_ms(const rgame_app *app) {
    (void)app; /* SDL's clock is global; app is taken for API consistency. */
    return SDL_GetTicks();
}

double rgame_app_fps(const rgame_app *app) {
    return app->fps_counter.fps;
}
