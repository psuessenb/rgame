#ifndef RGAME_FRAME_LOOP_H
#define RGAME_FRAME_LOOP_H

/*
 * Pure fixed-timestep + FPS logic — no SDL, no GL, no I/O.
 *
 * This is "layer 1" per CLAUDE.md's abstraction strategy: the tricky
 * time-accounting decisions live here as plain arithmetic on plain structs,
 * so they can be exercised by the Check suite without a window or clock.
 * core.c owns the real loop and feeds this real elapsed time from SDL.
 */

/*
 * Fixed-timestep accumulator. Real elapsed time is poured in each frame via
 * rgame_frame_loop_advance, which reports how many whole simulation ticks are
 * now due. Leftover sub-tick time is retained for next frame, so simulation
 * stays decoupled from a variable/vsync render rate.
 */
typedef struct {
    double accumulated_seconds;
} rgame_frame_loop;

void rgame_frame_loop_init(rgame_frame_loop *loop);

/*
 * Adds elapsed_seconds to the accumulator and returns how many ticks of
 * tick_seconds are now due, draining that much time from the accumulator.
 *
 * max_ticks_per_frame caps the ticks returned from a single call. If that cap
 * is hit, the remaining backlog is dropped (accumulator reset to 0) rather than
 * carried forward — this is the "spiral of death" guard: if a frame is so slow
 * the sim can't catch up within the cap, we let time slow down instead of
 * accumulating an ever-growing debt that makes every subsequent frame worse.
 */
int rgame_frame_loop_advance(rgame_frame_loop *loop, double elapsed_seconds,
                             double tick_seconds, int max_ticks_per_frame);

/*
 * Rolling frames-per-second counter. Counts frames over a ~1 second window and
 * republishes `fps` at the end of each window. For a debug readout, not
 * gameplay logic (see docs/c_engine_feature_specs.md section 1).
 */
typedef struct {
    int frame_count;
    double window_elapsed_seconds;
    double fps;
} rgame_fps_counter;

void rgame_fps_counter_init(rgame_fps_counter *counter);

/* Records one frame of dt_seconds; updates `fps` once the 1s window closes. */
void rgame_fps_counter_tick(rgame_fps_counter *counter, double dt_seconds);

#endif /* RGAME_FRAME_LOOP_H */
