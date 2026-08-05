#include <check.h>

#include "graphics/canvas.h"
#include "recording_backend.h"
#include "suites.h"

/*
 * The submit loop: what a prepared frame turns into as a sequence of backend
 * calls. This is the last piece of logic before real GL, and the recording
 * backend is what lets it be checked without a display.
 */

typedef struct {
    rgame_canvas canvas;
    rgame_recording_backend recorder;
} fixture;

static void fixture_begin(fixture *f) {
    rgame_canvas_init(&f->canvas);
    rgame_recording_backend_init(&f->recorder);
    rgame_canvas_begin_frame(&f->canvas, 800, 600);
}

static void fixture_submit(fixture *f) {
    rgame_canvas_end_frame(&f->canvas);
    rgame_draw_backend backend = rgame_recording_backend_interface(&f->recorder);
    rgame_canvas_submit(&f->canvas, &backend);
}

static void fixture_end(fixture *f) {
    rgame_recording_backend_destroy(&f->recorder);
    rgame_canvas_destroy(&f->canvas);
}

static void quad_at(rgame_canvas *c, float x, float y, double z) {
    float xy[8] = { x, y, x + 10.0f, y, x + 10.0f, y + 10.0f, x, y + 10.0f };
    rgame_canvas_quad(c, xy, RGAME_COLOR_WHITE, z);
}

static void textured_quad_at(rgame_canvas *c, unsigned int texture, float x, double z) {
    float xy[8] = { x, 0.0f, x + 10.0f, 0.0f, x + 10.0f, 10.0f, x, 10.0f };
    float uv[8] = { 0.0f, 0.0f, 1.0f, 0.0f, 1.0f, 1.0f, 0.0f, 1.0f };
    rgame_canvas_textured_quad(c, texture, xy, uv, RGAME_COLOR_WHITE, z);
}

static rgame_call_kind kind_at(const fixture *f, unsigned int index) {
    return rgame_recording_call(&f->recorder, index)->kind;
}

/* --- the frame envelope --- */

START_TEST(a_frame_is_wrapped_in_begin_and_end) {
    fixture f;
    fixture_begin(&f);
    quad_at(&f.canvas, 0.0f, 0.0f, 0.0);
    fixture_submit(&f);

    unsigned int calls = rgame_recording_call_count(&f.recorder);
    ck_assert_uint_gt(calls, 2);
    ck_assert_int_eq(kind_at(&f, 0), RGAME_CALL_BEGIN_FRAME);
    ck_assert_int_eq(kind_at(&f, calls - 1), RGAME_CALL_END_FRAME);

    fixture_end(&f);
}
END_TEST

START_TEST(begin_frame_receives_the_size_the_frame_was_begun_at) {
    fixture f;
    rgame_canvas_init(&f.canvas);
    rgame_recording_backend_init(&f.recorder);
    rgame_canvas_begin_frame(&f.canvas, 1024, 768);
    fixture_submit(&f);

    const rgame_recorded_call *call = rgame_recording_call(&f.recorder, 0);
    ck_assert_int_eq(call->width, 1024);
    ck_assert_int_eq(call->height, 768);

    fixture_end(&f);
}
END_TEST

START_TEST(an_empty_frame_is_still_begun_and_ended) {
    /* The real backend has to clear and present even when nothing was drawn,
     * or a frame with no content would show whatever was on screen before. */
    fixture f;
    fixture_begin(&f);
    fixture_submit(&f);

    ck_assert_uint_eq(rgame_recording_call_count(&f.recorder), 2);
    ck_assert_int_eq(kind_at(&f, 0), RGAME_CALL_BEGIN_FRAME);
    ck_assert_int_eq(kind_at(&f, 1), RGAME_CALL_END_FRAME);
    ck_assert_uint_eq(rgame_recording_count_of(&f.recorder, RGAME_CALL_DRAW_BATCH), 0);

    fixture_end(&f);
}
END_TEST

/* --- draws --- */

START_TEST(one_batch_becomes_one_draw_call) {
    fixture f;
    fixture_begin(&f);
    quad_at(&f.canvas, 0.0f, 0.0f, 1.0);
    quad_at(&f.canvas, 20.0f, 0.0f, 2.0);
    quad_at(&f.canvas, 40.0f, 0.0f, 3.0);
    fixture_submit(&f);

    /* Three quads, same texture and clip: one draw, not three. This is the
     * batching payoff, observed where it actually matters. */
    ck_assert_uint_eq(rgame_recording_count_of(&f.recorder, RGAME_CALL_DRAW_BATCH), 1);

    fixture_end(&f);
}
END_TEST

START_TEST(a_draw_call_carries_its_texture_and_vertex_run) {
    fixture f;
    fixture_begin(&f);
    textured_quad_at(&f.canvas, 42, 0.0f, 1.0);
    fixture_submit(&f);

    const rgame_recorded_call *draw = NULL;
    for (unsigned int i = 0; i < rgame_recording_call_count(&f.recorder); i++) {
        if (kind_at(&f, i) == RGAME_CALL_DRAW_BATCH) {
            draw = rgame_recording_call(&f.recorder, i);
        }
    }
    ck_assert_ptr_nonnull(draw);
    ck_assert_uint_eq(draw->texture, 42);
    ck_assert_uint_eq(draw->vertex_count, 6);

    /* The vertices the backend saw are the transformed ones, not the caller's. */
    const rgame_vertex *v = &rgame_recording_vertices(&f.recorder)[draw->first_vertex];
    ck_assert_float_eq_tol(v[0].x, 0.0f, 1e-3f);
    ck_assert_float_eq_tol(v[1].x, 10.0f, 1e-3f);

    fixture_end(&f);
}
END_TEST

START_TEST(the_backend_sees_transformed_positions) {
    fixture f;
    fixture_begin(&f);
    rgame_canvas_push_translate(&f.canvas, 100.0f, 50.0f);
    textured_quad_at(&f.canvas, 1, 0.0f, 1.0);
    rgame_canvas_pop(&f.canvas);
    fixture_submit(&f);

    const rgame_vertex *v = rgame_recording_vertices(&f.recorder);
    ck_assert_float_eq_tol(v[0].x, 100.0f, 1e-3f);
    ck_assert_float_eq_tol(v[0].y, 50.0f, 1e-3f);

    fixture_end(&f);
}
END_TEST

/* --- clip state --- */

START_TEST(the_clip_is_set_before_the_draw_that_needs_it) {
    fixture f;
    fixture_begin(&f);
    rgame_canvas_push_clip(&f.canvas, rgame_rect_make(10, 10, 100, 100));
    quad_at(&f.canvas, 0.0f, 0.0f, 1.0);
    rgame_canvas_pop(&f.canvas);
    fixture_submit(&f);

    /* begin, set_clip, draw, end — in that order. */
    ck_assert_uint_eq(rgame_recording_call_count(&f.recorder), 4);
    ck_assert_int_eq(kind_at(&f, 1), RGAME_CALL_SET_CLIP);
    ck_assert_int_eq(kind_at(&f, 2), RGAME_CALL_DRAW_BATCH);
    ck_assert_int_eq(rgame_recording_call(&f.recorder, 1)->clip.x, 10);

    fixture_end(&f);
}
END_TEST

START_TEST(an_unchanged_clip_is_not_re_issued_between_batches) {
    /*
     * Batches split on texture *or* clip, so two adjacent batches often share a
     * clip and differ only in texture. Re-issuing an identical scissor for each
     * would be a wasted state change on every frame — and nothing but a
     * call-recording test can see it, since the picture is the same either way.
     */
    fixture f;
    fixture_begin(&f);
    textured_quad_at(&f.canvas, 1, 0.0f, 1.0);
    textured_quad_at(&f.canvas, 2, 20.0f, 2.0);
    textured_quad_at(&f.canvas, 3, 40.0f, 3.0);
    fixture_submit(&f);

    ck_assert_uint_eq(rgame_recording_count_of(&f.recorder, RGAME_CALL_DRAW_BATCH), 3);
    ck_assert_uint_eq(rgame_recording_count_of(&f.recorder, RGAME_CALL_SET_CLIP), 1);

    fixture_end(&f);
}
END_TEST

START_TEST(a_changed_clip_is_re_issued) {
    fixture f;
    fixture_begin(&f);

    rgame_canvas_push_clip(&f.canvas, rgame_rect_make(0, 0, 400, 600));
    quad_at(&f.canvas, 0.0f, 0.0f, 1.0);
    rgame_canvas_pop(&f.canvas);

    rgame_canvas_push_clip(&f.canvas, rgame_rect_make(400, 0, 400, 600));
    quad_at(&f.canvas, 500.0f, 0.0f, 2.0);
    rgame_canvas_pop(&f.canvas);

    fixture_submit(&f);

    ck_assert_uint_eq(rgame_recording_count_of(&f.recorder, RGAME_CALL_SET_CLIP), 2);
    ck_assert_uint_eq(rgame_recording_count_of(&f.recorder, RGAME_CALL_DRAW_BATCH), 2);

    fixture_end(&f);
}
END_TEST

START_TEST(returning_to_an_earlier_clip_sets_it_again) {
    /* The loop tracks only the clip currently in force, not every clip it has
     * ever seen — going back to one still needs the scissor re-issued. */
    fixture f;
    fixture_begin(&f);

    rgame_canvas_push_clip(&f.canvas, rgame_rect_make(0, 0, 400, 600));
    quad_at(&f.canvas, 0.0f, 0.0f, 1.0);
    rgame_canvas_pop(&f.canvas);
    rgame_canvas_push_clip(&f.canvas, rgame_rect_make(400, 0, 400, 600));
    quad_at(&f.canvas, 500.0f, 0.0f, 2.0);
    rgame_canvas_pop(&f.canvas);
    rgame_canvas_push_clip(&f.canvas, rgame_rect_make(0, 0, 400, 600));
    quad_at(&f.canvas, 10.0f, 0.0f, 3.0);
    rgame_canvas_pop(&f.canvas);

    fixture_submit(&f);

    ck_assert_uint_eq(rgame_recording_count_of(&f.recorder, RGAME_CALL_SET_CLIP), 3);

    fixture_end(&f);
}
END_TEST

START_TEST(clips_and_draws_interleave_rather_than_being_grouped) {
    /*
     * Order matters, not just counts: each scissor must be issued immediately
     * before the draw it governs. Issuing every clip first and then every draw
     * would leave the last clip in force for all of them — a whole-frame
     * corruption that call *counts* alone would not notice.
     */
    fixture f;
    fixture_begin(&f);

    rgame_canvas_push_clip(&f.canvas, rgame_rect_make(0, 0, 400, 600));
    quad_at(&f.canvas, 0.0f, 0.0f, 1.0);
    rgame_canvas_pop(&f.canvas);
    rgame_canvas_push_clip(&f.canvas, rgame_rect_make(400, 0, 400, 600));
    quad_at(&f.canvas, 500.0f, 0.0f, 2.0);
    rgame_canvas_pop(&f.canvas);

    fixture_submit(&f);

    ck_assert_uint_eq(rgame_recording_call_count(&f.recorder), 6);
    ck_assert_int_eq(kind_at(&f, 0), RGAME_CALL_BEGIN_FRAME);
    ck_assert_int_eq(kind_at(&f, 1), RGAME_CALL_SET_CLIP);
    ck_assert_int_eq(kind_at(&f, 2), RGAME_CALL_DRAW_BATCH);
    ck_assert_int_eq(kind_at(&f, 3), RGAME_CALL_SET_CLIP);
    ck_assert_int_eq(kind_at(&f, 4), RGAME_CALL_DRAW_BATCH);
    ck_assert_int_eq(kind_at(&f, 5), RGAME_CALL_END_FRAME);

    fixture_end(&f);
}
END_TEST

START_TEST(each_draw_gets_its_own_slice_of_the_vertex_array) {
    /*
     * Every batch after the first starts partway into the prepared vertices.
     * Handing the backend the array's start each time would draw the first
     * batch's geometry over and over — invisible in any single-batch test.
     */
    fixture f;
    fixture_begin(&f);
    textured_quad_at(&f.canvas, 1, 0.0f, 1.0);
    textured_quad_at(&f.canvas, 2, 100.0f, 2.0);
    fixture_submit(&f);

    const rgame_recorded_call *first = NULL;
    const rgame_recorded_call *second = NULL;
    for (unsigned int i = 0; i < rgame_recording_call_count(&f.recorder); i++) {
        if (kind_at(&f, i) != RGAME_CALL_DRAW_BATCH) {
            continue;
        }
        if (!first) {
            first = rgame_recording_call(&f.recorder, i);
        } else if (!second) {
            second = rgame_recording_call(&f.recorder, i);
        }
    }
    ck_assert_ptr_nonnull(second);

    const rgame_vertex *v = rgame_recording_vertices(&f.recorder);
    ck_assert_float_eq_tol(v[first->first_vertex].x, 0.0f, 1e-3f);
    ck_assert_float_eq_tol(v[second->first_vertex].x, 100.0f, 1e-3f);

    fixture_end(&f);
}
END_TEST

/* --- split-screen, as the backend sees it --- */

START_TEST(split_screen_reaches_the_backend_as_two_clipped_draws) {
    fixture f;
    fixture_begin(&f);

    rgame_canvas_push_clip(&f.canvas, rgame_rect_make(0, 0, 400, 600));
    rgame_canvas_push_translate(&f.canvas, -1000.0f, 0.0f);
    quad_at(&f.canvas, 1000.0f, 100.0f, 5.0);
    rgame_canvas_pop(&f.canvas);
    rgame_canvas_pop(&f.canvas);

    rgame_canvas_push_clip(&f.canvas, rgame_rect_make(400, 0, 400, 600));
    rgame_canvas_push_translate(&f.canvas, -1600.0f, 0.0f);
    quad_at(&f.canvas, 2000.0f, 200.0f, 1.0);
    rgame_canvas_pop(&f.canvas);
    rgame_canvas_pop(&f.canvas);

    fixture_submit(&f);

    ck_assert_uint_eq(rgame_recording_count_of(&f.recorder, RGAME_CALL_SET_CLIP), 2);
    ck_assert_uint_eq(rgame_recording_count_of(&f.recorder, RGAME_CALL_DRAW_BATCH), 2);
    /* Player 2 sorted first (lower z), so its scissor is issued first. */
    ck_assert_int_eq(rgame_recording_call(&f.recorder, 1)->clip.x, 400);

    fixture_end(&f);
}
END_TEST

/* --- a partial backend --- */

START_TEST(a_backend_with_null_hooks_is_simply_skipped) {
    /* Every member is optional. A backend that only wants draw calls should be
     * able to leave the rest out rather than supply empty functions. */
    rgame_canvas canvas;
    rgame_canvas_init(&canvas);
    rgame_canvas_begin_frame(&canvas, 800, 600);
    quad_at(&canvas, 0.0f, 0.0f, 1.0);
    rgame_canvas_end_frame(&canvas);

    rgame_draw_backend empty = { 0 };
    rgame_canvas_submit(&canvas, &empty);

    rgame_recording_backend recorder;
    rgame_recording_backend_init(&recorder);
    rgame_draw_backend only_draw = { .draw_batch =
                                         rgame_recording_backend_interface(&recorder).draw_batch,
                                     .ctx = &recorder };
    rgame_canvas_submit(&canvas, &only_draw);

    ck_assert_uint_eq(rgame_recording_count_of(&recorder, RGAME_CALL_DRAW_BATCH), 1);
    ck_assert_uint_eq(rgame_recording_count_of(&recorder, RGAME_CALL_BEGIN_FRAME), 0);

    rgame_recording_backend_destroy(&recorder);
    rgame_canvas_destroy(&canvas);
}
END_TEST

START_TEST(submitting_with_no_backend_at_all_is_harmless) {
    rgame_canvas canvas;
    rgame_canvas_init(&canvas);
    rgame_canvas_begin_frame(&canvas, 800, 600);
    quad_at(&canvas, 0.0f, 0.0f, 1.0);
    rgame_canvas_end_frame(&canvas);

    rgame_draw_submit(rgame_canvas_queue(&canvas), NULL, 800, 600);
    rgame_draw_submit(NULL, NULL, 800, 600);

    rgame_canvas_destroy(&canvas);
}
END_TEST

Suite *backend_suite(void) {
    Suite *suite = suite_create("backend");

    TCase *tc_frame = tcase_create("frame");
    tcase_add_test(tc_frame, a_frame_is_wrapped_in_begin_and_end);
    tcase_add_test(tc_frame, begin_frame_receives_the_size_the_frame_was_begun_at);
    tcase_add_test(tc_frame, an_empty_frame_is_still_begun_and_ended);
    suite_add_tcase(suite, tc_frame);

    TCase *tc_draw = tcase_create("draws");
    tcase_add_test(tc_draw, one_batch_becomes_one_draw_call);
    tcase_add_test(tc_draw, a_draw_call_carries_its_texture_and_vertex_run);
    tcase_add_test(tc_draw, the_backend_sees_transformed_positions);
    tcase_add_test(tc_draw, each_draw_gets_its_own_slice_of_the_vertex_array);
    suite_add_tcase(suite, tc_draw);

    TCase *tc_clip = tcase_create("clip_state");
    tcase_add_test(tc_clip, the_clip_is_set_before_the_draw_that_needs_it);
    tcase_add_test(tc_clip, an_unchanged_clip_is_not_re_issued_between_batches);
    tcase_add_test(tc_clip, a_changed_clip_is_re_issued);
    tcase_add_test(tc_clip, returning_to_an_earlier_clip_sets_it_again);
    tcase_add_test(tc_clip, clips_and_draws_interleave_rather_than_being_grouped);
    tcase_add_test(tc_clip, split_screen_reaches_the_backend_as_two_clipped_draws);
    suite_add_tcase(suite, tc_clip);

    TCase *tc_partial = tcase_create("partial_backend");
    tcase_add_test(tc_partial, a_backend_with_null_hooks_is_simply_skipped);
    tcase_add_test(tc_partial, submitting_with_no_backend_at_all_is_harmless);
    suite_add_tcase(suite, tc_partial);

    return suite;
}
