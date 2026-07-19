#include <stdio.h>
#include <time.h>

#include "ctest/core.h"

static double seconds_since(struct timespec start, struct timespec end) {
    return (end.tv_sec - start.tv_sec) + (end.tv_nsec - start.tv_nsec) / 1e9;
}

int main(void) {
    ctest_app *app = ctest_app_create(800, 600, "ctest - SDL + OpenGL");
    if (!app) {
        fprintf(stderr, "Failed to create app\n");
        return 1;
    }

    struct timespec prev;
    clock_gettime(CLOCK_MONOTONIC, &prev);

    while (ctest_app_poll_events(app)) {
        struct timespec now;
        clock_gettime(CLOCK_MONOTONIC, &now);
        double dt = seconds_since(prev, now);
        prev = now;

        ctest_app_update(app, dt);
        ctest_app_render(app);
    }

    ctest_app_destroy(app);
    return 0;
}
