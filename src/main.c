#include <stdio.h>
#include <time.h>

#include "rgame/core.h"

static double seconds_since(struct timespec start, struct timespec end) {
    return (end.tv_sec - start.tv_sec) + (end.tv_nsec - start.tv_nsec) / 1e9;
}

int main(void) {
    rgame_app *app = rgame_app_create(800, 600, "rgame - SDL + OpenGL");
    if (!app) {
        fprintf(stderr, "Failed to create app\n");
        return 1;
    }

    struct timespec prev;
    clock_gettime(CLOCK_MONOTONIC, &prev);

    while (rgame_app_poll_events(app)) {
        struct timespec now;
        clock_gettime(CLOCK_MONOTONIC, &now);
        double dt = seconds_since(prev, now);
        prev = now;

        rgame_app_update(app, dt);
        rgame_app_render(app);
    }

    rgame_app_destroy(app);
    return 0;
}
