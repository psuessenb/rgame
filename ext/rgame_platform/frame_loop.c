#include "frame_loop.h"

void rgame_frame_loop_init(rgame_frame_loop *loop) {
    loop->accumulated_seconds = 0.0;
}

int rgame_frame_loop_advance(rgame_frame_loop *loop, double elapsed_seconds,
                             double tick_seconds, int max_ticks_per_frame) {
    loop->accumulated_seconds += elapsed_seconds;

    int ticks = 0;
    while (loop->accumulated_seconds >= tick_seconds && ticks < max_ticks_per_frame) {
        loop->accumulated_seconds -= tick_seconds;
        ticks++;
    }

    if (ticks == max_ticks_per_frame) {
        /* Hit the cap: we're behind. Drop the backlog so we don't spiral. */
        loop->accumulated_seconds = 0.0;
    }

    return ticks;
}

void rgame_fps_counter_init(rgame_fps_counter *counter) {
    counter->frame_count = 0;
    counter->window_elapsed_seconds = 0.0;
    counter->fps = 0.0;
}

void rgame_fps_counter_tick(rgame_fps_counter *counter, double dt_seconds) {
    counter->frame_count++;
    counter->window_elapsed_seconds += dt_seconds;

    if (counter->window_elapsed_seconds >= 1.0) {
        /* Divide by the real window length, not a hardcoded 1.0, since the
         * window usually overshoots slightly past 1 second. */
        counter->fps = counter->frame_count / counter->window_elapsed_seconds;
        counter->frame_count = 0;
        counter->window_elapsed_seconds = 0.0;
    }
}
