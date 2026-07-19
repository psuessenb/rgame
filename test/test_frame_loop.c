#include <check.h>
#include <stdlib.h>

#include "frame_loop.h"

/* --- rgame_frame_loop (fixed-timestep accumulator) --- */

START_TEST(advance_yields_one_tick_at_exact_tick_boundary) {
    rgame_frame_loop loop;
    rgame_frame_loop_init(&loop);

    int ticks = rgame_frame_loop_advance(&loop, 1.0 / 60.0, 1.0 / 60.0, 5);
    ck_assert_int_eq(ticks, 1);
}
END_TEST

START_TEST(advance_holds_sub_tick_time_then_fires_next_call) {
    rgame_frame_loop loop;
    rgame_frame_loop_init(&loop);

    /* Half a tick: not enough yet. */
    int first = rgame_frame_loop_advance(&loop, 0.5 / 60.0, 1.0 / 60.0, 5);
    ck_assert_int_eq(first, 0);

    /* Another half tick: the two halves now make one whole tick. */
    int second = rgame_frame_loop_advance(&loop, 0.5 / 60.0, 1.0 / 60.0, 5);
    ck_assert_int_eq(second, 1);
}
END_TEST

START_TEST(advance_caps_catch_up_and_drops_backlog) {
    rgame_frame_loop loop;
    rgame_frame_loop_init(&loop);

    /* Ten ticks' worth of time arrives at once, but the cap is 5. */
    int ticks = rgame_frame_loop_advance(&loop, 10.0 / 60.0, 1.0 / 60.0, 5);
    ck_assert_int_eq(ticks, 5);

    /* The 5-tick backlog was dropped, not carried: a quiet next frame is 0. */
    int next_frame = rgame_frame_loop_advance(&loop, 0.0, 1.0 / 60.0, 5);
    ck_assert_int_eq(next_frame, 0);
}
END_TEST

/* --- rgame_fps_counter --- */

START_TEST(fps_stays_zero_until_window_closes) {
    rgame_fps_counter counter;
    rgame_fps_counter_init(&counter);

    rgame_fps_counter_tick(&counter, 0.5);
    ck_assert_double_eq_tol(counter.fps, 0.0, 1e-9);
}
END_TEST

START_TEST(fps_reports_rate_after_one_second_window) {
    rgame_fps_counter counter;
    rgame_fps_counter_init(&counter);

    /* Two frames of exactly 0.5 s (exact in binary FP) close a 1.0 s window. */
    rgame_fps_counter_tick(&counter, 0.5);
    rgame_fps_counter_tick(&counter, 0.5);
    ck_assert_double_eq_tol(counter.fps, 2.0, 1e-9);
}
END_TEST

static Suite *frame_loop_suite(void) {
    Suite *suite = suite_create("frame_loop");

    TCase *tc_loop = tcase_create("accumulator");
    tcase_add_test(tc_loop, advance_yields_one_tick_at_exact_tick_boundary);
    tcase_add_test(tc_loop, advance_holds_sub_tick_time_then_fires_next_call);
    tcase_add_test(tc_loop, advance_caps_catch_up_and_drops_backlog);
    suite_add_tcase(suite, tc_loop);

    TCase *tc_fps = tcase_create("fps_counter");
    tcase_add_test(tc_fps, fps_stays_zero_until_window_closes);
    tcase_add_test(tc_fps, fps_reports_rate_after_one_second_window);
    suite_add_tcase(suite, tc_fps);

    return suite;
}

int main(void) {
    Suite *suite = frame_loop_suite();
    SRunner *runner = srunner_create(suite);

    srunner_run_all(runner, CK_NORMAL);
    int failed = srunner_ntests_failed(runner);
    srunner_free(runner);

    return failed == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
