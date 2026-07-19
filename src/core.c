#include "rgame/core.h"
#include "internal.h"

#include <SDL2/SDL.h>
#include <SDL2/SDL_opengl.h>
#include <math.h>
#include <stdlib.h>

struct rgame_app {
    SDL_Window *window;
    SDL_GLContext gl_context;
    int running;
    double angle_degrees;
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
    app->angle_degrees = 0.0;
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

int rgame_app_poll_events(rgame_app *app) {
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
    return app->running;
}

double rgame_wrap_angle_degrees(double angle_degrees, double delta_degrees) {
    double result = angle_degrees + delta_degrees;
    result = fmod(result, 360.0);
    if (result < 0.0) {
        result += 360.0;
    }
    return result;
}

void rgame_app_update(rgame_app *app, double dt_seconds) {
    double delta_degrees = dt_seconds * 90.0; /* 90 degrees/sec */
    app->angle_degrees = rgame_wrap_angle_degrees(app->angle_degrees, delta_degrees);
}

void rgame_app_render(rgame_app *app) {
    glClearColor(0.1f, 0.1f, 0.15f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();
    glRotated(app->angle_degrees, 0.0, 0.0, 1.0);

    glBegin(GL_TRIANGLES);
        glColor3f(1.0f, 0.0f, 0.0f); glVertex2f(0.0f, 0.6f);
        glColor3f(0.0f, 1.0f, 0.0f); glVertex2f(-0.6f, -0.4f);
        glColor3f(0.0f, 0.0f, 1.0f); glVertex2f(0.6f, -0.4f);
    glEnd();

    SDL_GL_SwapWindow(app->window);
}
