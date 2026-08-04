#include <check.h>

#include "primitives.h"
#include "recording.h"
#include "suites.h"

/*
 * Layer-1 tests for recording.c and rgame_canvas_replay: what gets baked, and
 * what comes back out when it is replayed somewhere else. No GL — a recording
 * is a vertex array and a list of texture spans, and everything interesting
 * about it is arithmetic.
 */

#define TOL 1e-3f

static void begin(rgame_canvas *c) {
    rgame_canvas_init(c);
    rgame_canvas_begin_frame(c, 800, 600);
}

/*
 * Bakes whatever `draws` puts on a scratch canvas. This is the shape the app
 * uses too: draw into a canvas of its own, prepare it, copy the result out.
 */
static void bake(rgame_recording *out, void (*draws)(rgame_canvas *)) {
    rgame_canvas scratch;
    begin(&scratch);
    draws(&scratch);
    rgame_canvas_end_frame(&scratch);

    ck_assert_int_eq(rgame_recording_capture(out, rgame_canvas_queue(&scratch)), 1);
    rgame_canvas_destroy(&scratch);
}

static const rgame_vertex *vertex(const rgame_canvas *c, unsigned int index) {
    return &rgame_draw_queue_vertices(rgame_canvas_queue(c))[index];
}

static void ck_vertex_xy(const rgame_canvas *c, unsigned int index, float x, float y) {
    ck_assert_float_eq_tol(vertex(c, index)->x, x, TOL);
    ck_assert_float_eq_tol(vertex(c, index)->y, y, TOL);
}

/* --- what draws into a recording --- */

static void one_red_rect(rgame_canvas *c) {
    rgame_prim_rect(c, 10.0f, 20.0f, 30.0f, 40.0f, 0xFF0000FFu, 0.0);
}

static void three_rects(rgame_canvas *c) {
    rgame_prim_rect(c, 0.0f, 0.0f, 10.0f, 10.0f, RGAME_COLOR_WHITE, 0.0);
    rgame_prim_rect(c, 20.0f, 0.0f, 10.0f, 10.0f, RGAME_COLOR_WHITE, 0.0);
    rgame_prim_rect(c, 40.0f, 0.0f, 10.0f, 10.0f, RGAME_COLOR_WHITE, 0.0);
}

static void nothing_at_all(rgame_canvas *c) {
    (void)c;
}

/* A sheet with a memorable GL name, so a recording that loses or confuses a
 * texture is visible in an assertion. The view is destroyed as soon as it has
 * been drawn: the draw copies its vertices (GL name included) into the queue,
 * so nothing downstream still needs it. */
static rgame_texture sheet_named(unsigned int name, int width, int height) {
    rgame_texture_sheet *sheet = rgame_texture_sheet_create(name, width, height);
    rgame_texture view = rgame_texture_whole(sheet);
    rgame_texture_sheet_release(sheet, NULL);
    return view;
}

/* One sprite from texture 7 at the origin, then one from texture 9 further
 * right: two batches, in that order. */
static void two_textures(rgame_canvas *c) {
    rgame_texture first = sheet_named(7, 16, 16);
    rgame_texture second = sheet_named(9, 16, 16);

    rgame_prim_image(c, &first, 0.0f, 0.0f, RGAME_COLOR_WHITE, 0.0);
    rgame_prim_image(c, &second, 100.0f, 0.0f, RGAME_COLOR_WHITE, 1.0);

    rgame_texture_destroy(&first, NULL);
    rgame_texture_destroy(&second, NULL);
}

/* The bottom-right quarter of a sheet, so its UVs are 0.5..1 rather than the
 * whole square — a dropped UV reads as 0 and is caught. */
static void one_sprite_from_a_sheet(rgame_canvas *c) {
    rgame_texture sheet = sheet_named(7, 64, 64);
    rgame_texture tile = {0};
    rgame_texture_subimage(&sheet, 32, 32, 32, 32, &tile);

    rgame_prim_image(c, &tile, 0.0f, 0.0f, RGAME_COLOR_WHITE, 0.0);

    rgame_texture_destroy(&tile, NULL);
    rgame_texture_destroy(&sheet, NULL);
}

/* --- capture --- */

START_TEST(a_recording_keeps_the_baked_vertices) {
    rgame_recording recording;
    bake(&recording, one_red_rect);

    ck_assert_uint_eq(rgame_recording_vertex_count(&recording), 6);
    ck_assert_uint_eq(rgame_recording_batch_count(&recording), 1);

    rgame_recording_destroy(&recording);
}
END_TEST

START_TEST(many_draws_of_one_texture_bake_into_one_batch) {
    /* This is the whole point: the per-tile work happens once, and what is
     * left to do every frame is one command, not one per tile. */
    rgame_recording recording;
    bake(&recording, three_rects);

    ck_assert_uint_eq(rgame_recording_vertex_count(&recording), 18);
    ck_assert_uint_eq(rgame_recording_batch_count(&recording), 1);

    rgame_recording_destroy(&recording);
}
END_TEST

START_TEST(an_empty_recording_captures_successfully) {
    rgame_recording recording;
    bake(&recording, nothing_at_all);

    ck_assert_uint_eq(rgame_recording_batch_count(&recording), 0);
    ck_assert_uint_eq(rgame_recording_vertex_count(&recording), 0);

    rgame_recording_destroy(&recording);
}
END_TEST

START_TEST(destroying_a_recording_twice_is_harmless) {
    rgame_recording recording;
    bake(&recording, one_red_rect);

    rgame_recording_destroy(&recording);
    rgame_recording_destroy(&recording);

    ck_assert_uint_eq(rgame_recording_vertex_count(&recording), 0);
}
END_TEST

START_TEST(a_recording_reports_the_bounds_of_what_it_holds) {
    rgame_recording recording;
    bake(&recording, one_red_rect);

    float min_x = 0.0f, min_y = 0.0f, max_x = 0.0f, max_y = 0.0f;
    rgame_recording_bounds(&recording, &min_x, &min_y, &max_x, &max_y);

    ck_assert_float_eq_tol(min_x, 10.0f, TOL);
    ck_assert_float_eq_tol(min_y, 20.0f, TOL);
    ck_assert_float_eq_tol(max_x, 40.0f, TOL);
    ck_assert_float_eq_tol(max_y, 60.0f, TOL);

    rgame_recording_destroy(&recording);
}
END_TEST

START_TEST(an_empty_recording_has_zero_bounds) {
    rgame_recording recording;
    bake(&recording, nothing_at_all);

    float min_x = 9.0f, min_y = 9.0f, max_x = 9.0f, max_y = 9.0f;
    rgame_recording_bounds(&recording, &min_x, &min_y, &max_x, &max_y);

    ck_assert_float_eq_tol(min_x, 0.0f, TOL);
    ck_assert_float_eq_tol(max_y, 0.0f, TOL);

    rgame_recording_destroy(&recording);
}
END_TEST

/* --- replay --- */

START_TEST(replaying_at_the_origin_reproduces_the_baked_geometry) {
    rgame_recording recording;
    bake(&recording, one_red_rect);

    rgame_canvas c;
    begin(&c);
    rgame_canvas_replay(&c, &recording, 0.0f, 0.0f, RGAME_COLOR_WHITE, 0.0);
    rgame_canvas_end_frame(&c);

    ck_assert_uint_eq(rgame_draw_queue_vertex_count(rgame_canvas_queue(&c)), 6);
    ck_vertex_xy(&c, 0, 10.0f, 20.0f);
    ck_vertex_xy(&c, 2, 40.0f, 60.0f);

    rgame_canvas_destroy(&c);
    rgame_recording_destroy(&recording);
}
END_TEST

START_TEST(replaying_somewhere_else_offsets_every_vertex) {
    rgame_recording recording;
    bake(&recording, one_red_rect);

    rgame_canvas c;
    begin(&c);
    rgame_canvas_replay(&c, &recording, 100.0f, 200.0f, RGAME_COLOR_WHITE, 0.0);
    rgame_canvas_end_frame(&c);

    ck_vertex_xy(&c, 0, 110.0f, 220.0f);
    ck_vertex_xy(&c, 2, 140.0f, 260.0f);

    rgame_canvas_destroy(&c);
    rgame_recording_destroy(&recording);
}
END_TEST

START_TEST(a_replay_costs_one_command_per_baked_batch) {
    /* Three tiles baked, one command replayed — the saving this exists for.
     * Without it a replay would re-append every original command. */
    rgame_recording recording;
    bake(&recording, three_rects);

    rgame_canvas c;
    begin(&c);
    rgame_canvas_replay(&c, &recording, 0.0f, 0.0f, RGAME_COLOR_WHITE, 0.0);

    ck_assert_uint_eq(rgame_draw_queue_command_count(rgame_canvas_queue(&c)), 1);

    rgame_canvas_end_frame(&c);
    ck_assert_uint_eq(rgame_draw_queue_vertex_count(rgame_canvas_queue(&c)), 18);

    rgame_canvas_destroy(&c);
    rgame_recording_destroy(&recording);
}
END_TEST

START_TEST(a_replay_goes_through_the_transform_in_effect_at_replay_time) {
    /* A baked layer scrolling under a camera: the recording never changes, the
     * translate does. */
    rgame_recording recording;
    bake(&recording, one_red_rect);

    rgame_canvas c;
    begin(&c);
    rgame_canvas_push_translate(&c, -5.0f, -7.0f);
    rgame_canvas_replay(&c, &recording, 0.0f, 0.0f, RGAME_COLOR_WHITE, 0.0);
    rgame_canvas_pop(&c);
    rgame_canvas_end_frame(&c);

    ck_vertex_xy(&c, 0, 5.0f, 13.0f);

    rgame_canvas_destroy(&c);
    rgame_recording_destroy(&recording);
}
END_TEST

START_TEST(the_offset_is_applied_before_the_transform_not_after) {
    /* The order matters as soon as the transform is not a translation: an
     * offset of 10 under a 2x scale must move the replay 20 pixels, because the
     * offset is in the recording's coordinates and the scale is the world's. */
    rgame_recording recording;
    bake(&recording, one_red_rect);

    rgame_canvas c;
    begin(&c);
    rgame_canvas_push_scale(&c, 2.0f, 2.0f);
    rgame_canvas_replay(&c, &recording, 10.0f, 0.0f, RGAME_COLOR_WHITE, 0.0);
    rgame_canvas_pop(&c);
    rgame_canvas_end_frame(&c);

    ck_vertex_xy(&c, 0, 40.0f, 40.0f); /* (10 + 10) * 2, 20 * 2 */

    rgame_canvas_destroy(&c);
    rgame_recording_destroy(&recording);
}
END_TEST

START_TEST(a_replay_takes_the_clip_in_effect_at_replay_time) {
    rgame_recording recording;
    bake(&recording, one_red_rect);

    rgame_canvas c;
    begin(&c);
    rgame_canvas_push_clip(&c, rgame_rect_make(0, 0, 25, 25));
    rgame_canvas_replay(&c, &recording, 0.0f, 0.0f, RGAME_COLOR_WHITE, 0.0);
    rgame_canvas_pop(&c);
    rgame_canvas_end_frame(&c);

    const rgame_draw_batch *batch = rgame_draw_queue_batch(rgame_canvas_queue(&c), 0);
    ck_assert_int_eq(batch->clip.w, 25);
    ck_assert_int_eq(batch->clip.h, 25);

    rgame_canvas_destroy(&c);
    rgame_recording_destroy(&recording);
}
END_TEST

START_TEST(a_replay_lands_at_the_z_it_is_given_not_the_one_it_was_baked_at) {
    rgame_canvas scratch;
    begin(&scratch);
    /* Baked far in front, replayed far behind: the recording's own z values
     * decide the order *within* it, and nothing more. */
    rgame_prim_rect(&scratch, 0.0f, 0.0f, 10.0f, 10.0f, RGAME_COLOR_WHITE, 900.0);
    rgame_canvas_end_frame(&scratch);
    rgame_recording recording;
    rgame_recording_capture(&recording, rgame_canvas_queue(&scratch));
    rgame_canvas_destroy(&scratch);

    rgame_canvas c;
    begin(&c);
    rgame_canvas_replay(&c, &recording, 0.0f, 0.0f, RGAME_COLOR_WHITE, 1.0);
    rgame_prim_rect(&c, 0.0f, 0.0f, 10.0f, 10.0f, RGAME_COLOR_WHITE, 2.0);
    rgame_canvas_end_frame(&c);

    /* The later rect sorts after the replay, so the replay's vertices come
     * first in the prepared array. */
    ck_assert_uint_eq(rgame_draw_queue_vertex_count(rgame_canvas_queue(&c)), 12);
    ck_vertex_xy(&c, 0, 0.0f, 0.0f);

    rgame_canvas_destroy(&c);
    rgame_recording_destroy(&recording);
}
END_TEST

START_TEST(the_painter_order_baked_into_a_recording_survives_replay) {
    /* Two overlapping rects baked at different z. Replayed they share one z,
     * so their relative order has to come from the order they were baked in.
     */
    rgame_canvas scratch;
    begin(&scratch);
    rgame_prim_rect(&scratch, 0.0f, 0.0f, 10.0f, 10.0f, 0xFF0000FFu, 5.0);  /* behind */
    rgame_prim_rect(&scratch, 1.0f, 1.0f, 10.0f, 10.0f, 0x0000FFFFu, 1.0);  /* in front? no */
    rgame_canvas_end_frame(&scratch);
    rgame_recording recording;
    rgame_recording_capture(&recording, rgame_canvas_queue(&scratch));
    rgame_canvas_destroy(&scratch);

    rgame_canvas c;
    begin(&c);
    rgame_canvas_replay(&c, &recording, 0.0f, 0.0f, RGAME_COLOR_WHITE, 0.0);
    rgame_canvas_end_frame(&c);

    /* z 1 sorted before z 5 when baked, so the blue rect's vertices come first
     * and the red one is painted over it — exactly as it was when baked. */
    ck_vertex_xy(&c, 0, 1.0f, 1.0f);
    ck_vertex_xy(&c, 6, 0.0f, 0.0f);

    rgame_canvas_destroy(&c);
    rgame_recording_destroy(&recording);
}
END_TEST

START_TEST(a_white_tint_leaves_the_recorded_colours_alone) {
    rgame_recording recording;
    bake(&recording, one_red_rect);

    rgame_canvas c;
    begin(&c);
    rgame_canvas_replay(&c, &recording, 0.0f, 0.0f, RGAME_COLOR_WHITE, 0.0);
    rgame_canvas_end_frame(&c);

    const rgame_vertex *v = vertex(&c, 0);
    ck_assert_uint_eq(v->rgba[0], 255);
    ck_assert_uint_eq(v->rgba[1], 0);
    ck_assert_uint_eq(v->rgba[2], 0);
    ck_assert_uint_eq(v->rgba[3], 255);

    rgame_canvas_destroy(&c);
    rgame_recording_destroy(&recording);
}
END_TEST

START_TEST(a_tint_multiplies_the_recorded_colours) {
    /* The layer being replaced could only draw a recording in white. There is
     * no reason to inherit that, and fading a baked layer out is the obvious
     * thing to want. */
    rgame_canvas scratch;
    begin(&scratch);
    rgame_prim_rect(&scratch, 0.0f, 0.0f, 10.0f, 10.0f, 0xFFFFFFFFu, 0.0);
    rgame_canvas_end_frame(&scratch);
    rgame_recording recording;
    rgame_recording_capture(&recording, rgame_canvas_queue(&scratch));
    rgame_canvas_destroy(&scratch);

    rgame_canvas c;
    begin(&c);
    /* Half green, half alpha. */
    rgame_canvas_replay(&c, &recording, 0.0f, 0.0f, 0x00FF0080u, 0.0);
    rgame_canvas_end_frame(&c);

    const rgame_vertex *v = vertex(&c, 0);
    ck_assert_uint_eq(v->rgba[0], 0);
    ck_assert_uint_eq(v->rgba[1], 255);
    ck_assert_uint_eq(v->rgba[2], 0);
    ck_assert_uint_eq(v->rgba[3], 128);

    rgame_canvas_destroy(&c);
    rgame_recording_destroy(&recording);
}
END_TEST

START_TEST(replaying_a_destroyed_or_missing_recording_draws_nothing) {
    rgame_recording recording;
    bake(&recording, one_red_rect);
    rgame_recording_destroy(&recording);

    rgame_canvas c;
    begin(&c);
    rgame_canvas_replay(&c, &recording, 0.0f, 0.0f, RGAME_COLOR_WHITE, 0.0);
    rgame_canvas_replay(&c, NULL, 0.0f, 0.0f, RGAME_COLOR_WHITE, 0.0);
    rgame_canvas_end_frame(&c);

    ck_assert_uint_eq(rgame_draw_queue_vertex_count(rgame_canvas_queue(&c)), 0);

    rgame_canvas_destroy(&c);
}
END_TEST

START_TEST(a_recording_can_be_replayed_many_times_in_one_frame) {
    /* The tile map draws its baked layer once, but a game that stamps the same
     * bush across a field replays one recording dozens of times. */
    rgame_recording recording;
    bake(&recording, one_red_rect);

    rgame_canvas c;
    begin(&c);
    for (int i = 0; i < 5; i++) {
        rgame_canvas_replay(&c, &recording, (float)(i * 100), 0.0f, RGAME_COLOR_WHITE, 0.0);
    }
    rgame_canvas_end_frame(&c);

    ck_assert_uint_eq(rgame_draw_queue_vertex_count(rgame_canvas_queue(&c)), 30);
    ck_vertex_xy(&c, 0, 10.0f, 20.0f);
    ck_vertex_xy(&c, 24, 410.0f, 20.0f);
    /* Same texture, same clip, same z: the five replays merge into one call. */
    ck_assert_uint_eq(rgame_draw_queue_batch_count(rgame_canvas_queue(&c)), 1);

    rgame_canvas_destroy(&c);
    rgame_recording_destroy(&recording);
}
END_TEST

START_TEST(a_recording_keeps_each_texture_and_its_own_vertices) {
    rgame_recording recording;
    bake(&recording, two_textures);

    /* Two textures cannot share a GL call, so they cannot share a batch. */
    ck_assert_uint_eq(rgame_recording_batch_count(&recording), 2);
    ck_assert_uint_eq(rgame_recording_vertex_count(&recording), 12);
    ck_assert_uint_eq(recording.batches[0].texture, 7);
    ck_assert_uint_eq(recording.batches[1].texture, 9);
    /* And each batch points at its own span, not both at the first. */
    ck_assert_uint_eq(recording.batches[0].first_vertex, 0);
    ck_assert_uint_eq(recording.batches[1].first_vertex, 6);

    rgame_recording_destroy(&recording);
}
END_TEST

START_TEST(replaying_reproduces_every_batch_with_its_texture) {
    rgame_recording recording;
    bake(&recording, two_textures);

    rgame_canvas c;
    begin(&c);
    rgame_canvas_replay(&c, &recording, 10.0f, 0.0f, RGAME_COLOR_WHITE, 0.0);
    rgame_canvas_end_frame(&c);

    ck_assert_uint_eq(rgame_draw_queue_batch_count(rgame_canvas_queue(&c)), 2);
    ck_assert_uint_eq(rgame_draw_queue_batch(rgame_canvas_queue(&c), 0)->texture, 7);
    ck_assert_uint_eq(rgame_draw_queue_batch(rgame_canvas_queue(&c), 1)->texture, 9);

    /* Both batches were replayed, each from its own recorded vertices. */
    ck_assert_uint_eq(rgame_draw_queue_vertex_count(rgame_canvas_queue(&c)), 12);
    ck_vertex_xy(&c, 0, 10.0f, 0.0f);
    ck_vertex_xy(&c, 6, 110.0f, 0.0f);

    rgame_recording_destroy(&recording);
    rgame_canvas_destroy(&c);
}
END_TEST

START_TEST(a_replay_keeps_the_recorded_texture_coordinates) {
    /* Position is not enough: a sprite whose UVs were lost draws the wrong
     * part of its sheet at exactly the right place. */
    rgame_recording recording;
    bake(&recording, one_sprite_from_a_sheet);

    rgame_canvas c;
    begin(&c);
    rgame_canvas_replay(&c, &recording, 0.0f, 0.0f, RGAME_COLOR_WHITE, 0.0);
    rgame_canvas_end_frame(&c);

    ck_assert_float_eq_tol(vertex(&c, 0)->u, 0.5f, TOL);
    ck_assert_float_eq_tol(vertex(&c, 0)->v, 0.5f, TOL);
    ck_assert_float_eq_tol(vertex(&c, 1)->u, 1.0f, TOL);
    ck_assert_float_eq_tol(vertex(&c, 2)->v, 1.0f, TOL);

    rgame_recording_destroy(&recording);
    rgame_canvas_destroy(&c);
}
END_TEST

Suite *recording_suite(void) {
    Suite *suite = suite_create("recording");
    TCase *tc = tcase_create("core");

    tcase_add_test(tc, a_recording_keeps_the_baked_vertices);
    tcase_add_test(tc, many_draws_of_one_texture_bake_into_one_batch);
    tcase_add_test(tc, an_empty_recording_captures_successfully);
    tcase_add_test(tc, destroying_a_recording_twice_is_harmless);
    tcase_add_test(tc, a_recording_reports_the_bounds_of_what_it_holds);
    tcase_add_test(tc, an_empty_recording_has_zero_bounds);
    tcase_add_test(tc, a_recording_keeps_each_texture_and_its_own_vertices);

    tcase_add_test(tc, replaying_at_the_origin_reproduces_the_baked_geometry);
    tcase_add_test(tc, replaying_somewhere_else_offsets_every_vertex);
    tcase_add_test(tc, a_replay_costs_one_command_per_baked_batch);
    tcase_add_test(tc, replaying_reproduces_every_batch_with_its_texture);
    tcase_add_test(tc, a_replay_keeps_the_recorded_texture_coordinates);
    tcase_add_test(tc, a_replay_goes_through_the_transform_in_effect_at_replay_time);
    tcase_add_test(tc, the_offset_is_applied_before_the_transform_not_after);
    tcase_add_test(tc, a_replay_takes_the_clip_in_effect_at_replay_time);
    tcase_add_test(tc, a_replay_lands_at_the_z_it_is_given_not_the_one_it_was_baked_at);
    tcase_add_test(tc, the_painter_order_baked_into_a_recording_survives_replay);
    tcase_add_test(tc, a_white_tint_leaves_the_recorded_colours_alone);
    tcase_add_test(tc, a_tint_multiplies_the_recorded_colours);
    tcase_add_test(tc, replaying_a_destroyed_or_missing_recording_draws_nothing);
    tcase_add_test(tc, a_recording_can_be_replayed_many_times_in_one_frame);

    suite_add_tcase(suite, tc);
    return suite;
}
