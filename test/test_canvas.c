#include <check.h>

#include "canvas.h"
#include "suites.h"

/*
 * The canvas is exercised end to end: draw through it, end the frame, and read
 * the prepared batches back. Still no SDL and no window — everything from the
 * caller's coordinates to the batched vertices is arithmetic.
 */

#define TOL 1e-3f

static void begin(rgame_canvas *c) {
    rgame_canvas_init(c);
    rgame_canvas_begin_frame(c, 800, 600);
}

/* A 10x10 quad with its top-left at (x, y), in the caller's local space. */
static void quad_at(rgame_canvas *c, float x, float y, rgame_color color, double z) {
    float xy[8] = { x, y, x + 10.0f, y, x + 10.0f, y + 10.0f, x, y + 10.0f };
    rgame_canvas_quad(c, xy, color, z);
}

static const rgame_vertex *vertex(const rgame_canvas *c, unsigned int index) {
    return &rgame_draw_queue_vertices(rgame_canvas_queue(c))[index];
}

static void ck_vertex_xy(const rgame_canvas *c, unsigned int index, float x, float y) {
    ck_assert_float_eq_tol(vertex(c, index)->x, x, TOL);
    ck_assert_float_eq_tol(vertex(c, index)->y, y, TOL);
}

static const rgame_draw_batch *batch(const rgame_canvas *c, unsigned int index) {
    return rgame_draw_queue_batch(rgame_canvas_queue(c), index);
}

static unsigned int batch_count(const rgame_canvas *c) {
    return rgame_draw_queue_batch_count(rgame_canvas_queue(c));
}

/* --- primitives --- */

START_TEST(a_quad_becomes_two_triangles_in_loop_order) {
    rgame_canvas c;
    begin(&c);

    /* Corners: top-left, top-right, bottom-right, bottom-left. */
    quad_at(&c, 0.0f, 0.0f, RGAME_COLOR_WHITE, 0.0);
    rgame_canvas_end_frame(&c);

    ck_assert_uint_eq(rgame_draw_queue_vertex_count(rgame_canvas_queue(&c)), 6);
    /* Triangle 0-1-2 then 0-2-3. */
    ck_vertex_xy(&c, 0, 0.0f, 0.0f);
    ck_vertex_xy(&c, 1, 10.0f, 0.0f);
    ck_vertex_xy(&c, 2, 10.0f, 10.0f);
    ck_vertex_xy(&c, 3, 0.0f, 0.0f);
    ck_vertex_xy(&c, 4, 10.0f, 10.0f);
    ck_vertex_xy(&c, 5, 0.0f, 10.0f);

    rgame_canvas_destroy(&c);
}
END_TEST

START_TEST(a_triangle_keeps_its_three_points) {
    rgame_canvas c;
    begin(&c);

    float xy[6] = { 1.0f, 2.0f, 3.0f, 4.0f, 5.0f, 6.0f };
    rgame_canvas_triangle(&c, xy, RGAME_COLOR_WHITE, 0.0);
    rgame_canvas_end_frame(&c);

    ck_assert_uint_eq(rgame_draw_queue_vertex_count(rgame_canvas_queue(&c)), 3);
    ck_vertex_xy(&c, 0, 1.0f, 2.0f);
    ck_vertex_xy(&c, 2, 5.0f, 6.0f);

    rgame_canvas_destroy(&c);
}
END_TEST

START_TEST(the_colour_reaches_the_vertex_in_gl_byte_order) {
    /* The renderer's whole colour path in one assertion: a packed 0xRRGGBBAA
     * must arrive as R, G, B, A bytes, not as the word's own byte layout. */
    rgame_canvas c;
    begin(&c);

    quad_at(&c, 0.0f, 0.0f, rgame_color_rgba(0x11, 0x22, 0x33, 0x44), 0.0);
    rgame_canvas_end_frame(&c);

    ck_assert_uint_eq(vertex(&c, 0)->rgba[0], 0x11);
    ck_assert_uint_eq(vertex(&c, 0)->rgba[1], 0x22);
    ck_assert_uint_eq(vertex(&c, 0)->rgba[2], 0x33);
    ck_assert_uint_eq(vertex(&c, 0)->rgba[3], 0x44);

    rgame_canvas_destroy(&c);
}
END_TEST

START_TEST(a_textured_quad_carries_its_texture_and_uvs) {
    rgame_canvas c;
    begin(&c);

    float xy[8] = { 0.0f, 0.0f, 10.0f, 0.0f, 10.0f, 10.0f, 0.0f, 10.0f };
    float uv[8] = { 0.0f, 0.0f, 1.0f, 0.0f, 1.0f, 1.0f, 0.0f, 1.0f };
    rgame_canvas_textured_quad(&c, 42, xy, uv, RGAME_COLOR_WHITE, 0.0);
    rgame_canvas_end_frame(&c);

    ck_assert_uint_eq(batch_count(&c), 1);
    ck_assert_uint_eq(batch(&c, 0)->texture, 42);
    /* UVs follow the same corner order as the positions. */
    ck_assert_float_eq_tol(vertex(&c, 1)->u, 1.0f, TOL);
    ck_assert_float_eq_tol(vertex(&c, 1)->v, 0.0f, TOL);
    ck_assert_float_eq_tol(vertex(&c, 5)->u, 0.0f, TOL);
    ck_assert_float_eq_tol(vertex(&c, 5)->v, 1.0f, TOL);

    rgame_canvas_destroy(&c);
}
END_TEST

/* --- transforms --- */

START_TEST(a_quad_drawn_inside_a_translate_lands_translated) {
    rgame_canvas c;
    begin(&c);

    rgame_canvas_push_translate(&c, 100.0f, 50.0f);
    quad_at(&c, 0.0f, 0.0f, RGAME_COLOR_WHITE, 0.0);
    rgame_canvas_pop(&c);
    rgame_canvas_end_frame(&c);

    ck_vertex_xy(&c, 0, 100.0f, 50.0f);
    ck_vertex_xy(&c, 1, 110.0f, 50.0f);

    rgame_canvas_destroy(&c);
}
END_TEST

START_TEST(nested_transforms_compose_inner_first) {
    rgame_canvas c;
    begin(&c);

    rgame_canvas_push_translate(&c, 100.0f, 0.0f);
    rgame_canvas_push_rotate(&c, 90.0f, 0.0f, 0.0f);
    float xy[6] = { 1.0f, 0.0f, 1.0f, 0.0f, 1.0f, 0.0f };
    rgame_canvas_triangle(&c, xy, RGAME_COLOR_WHITE, 0.0);
    rgame_canvas_pop(&c);
    rgame_canvas_pop(&c);
    rgame_canvas_end_frame(&c);

    /* Rotated first — (1,0) clockwise to (0,1) — then translated. */
    ck_vertex_xy(&c, 0, 100.0f, 1.0f);

    rgame_canvas_destroy(&c);
}
END_TEST

START_TEST(popping_a_transform_restores_the_previous_one) {
    rgame_canvas c;
    begin(&c);

    rgame_canvas_push_translate(&c, 100.0f, 0.0f);
    rgame_canvas_pop(&c);
    quad_at(&c, 5.0f, 5.0f, RGAME_COLOR_WHITE, 0.0);
    rgame_canvas_end_frame(&c);

    ck_vertex_xy(&c, 0, 5.0f, 5.0f);
    ck_assert_int_eq(rgame_canvas_depth(&c), 0);

    rgame_canvas_destroy(&c);
}
END_TEST

/* --- clipping --- */

START_TEST(a_quad_carries_the_current_clip_into_its_command) {
    rgame_canvas c;
    begin(&c);

    rgame_canvas_push_clip(&c, rgame_rect_make(10, 20, 30, 40));
    quad_at(&c, 0.0f, 0.0f, RGAME_COLOR_WHITE, 0.0);
    rgame_canvas_pop(&c);
    rgame_canvas_end_frame(&c);

    ck_assert_uint_eq(batch_count(&c), 1);
    ck_assert_int_eq(batch(&c, 0)->clip.x, 10);
    ck_assert_int_eq(batch(&c, 0)->clip.y, 20);
    ck_assert_int_eq(batch(&c, 0)->clip.w, 30);
    ck_assert_int_eq(batch(&c, 0)->clip.h, 40);

    rgame_canvas_destroy(&c);
}
END_TEST

START_TEST(a_clip_pushed_inside_a_translate_moves_with_it) {
    /*
     * The measured behaviour of the layer being replaced: a clip at x 0..20
     * inside a translate of 50 clips x 50..70. The clip stack itself is pure
     * screen space, so this mapping is the canvas's job.
     */
    rgame_canvas c;
    begin(&c);

    rgame_canvas_push_translate(&c, 50.0f, 0.0f);
    rgame_canvas_push_clip(&c, rgame_rect_make(0, 0, 20, 600));
    quad_at(&c, 0.0f, 0.0f, RGAME_COLOR_WHITE, 0.0);
    rgame_canvas_pop(&c);
    rgame_canvas_pop(&c);
    rgame_canvas_end_frame(&c);

    ck_assert_int_eq(batch(&c, 0)->clip.x, 50);
    ck_assert_int_eq(batch(&c, 0)->clip.w, 20);

    rgame_canvas_destroy(&c);
}
END_TEST

START_TEST(a_rotated_clip_becomes_its_bounding_box) {
    /* A scissor rect cannot be rotated, so the bounding box is used — which
     * clips less than asked rather than more. A 45-degree turn of a 100-wide
     * square about its centre spans about 141 units. */
    rgame_canvas c;
    begin(&c);

    rgame_canvas_push_rotate(&c, 45.0f, 50.0f, 50.0f);
    rgame_canvas_push_clip(&c, rgame_rect_make(0, 0, 100, 100));
    quad_at(&c, 0.0f, 0.0f, RGAME_COLOR_WHITE, 0.0);
    rgame_canvas_pop(&c);
    rgame_canvas_pop(&c);
    rgame_canvas_end_frame(&c);

    /*
     * Rotating a 100-wide square 45 degrees about its centre gives a bounding
     * box spanning roughly -21..121 — wider than the square, which is the
     * "clips less than asked" direction. The negative side is then clamped
     * away by the window, because every clip is intersected with it.
     */
    rgame_rect clip = batch(&c, 0)->clip;
    ck_assert_int_eq(clip.x, 0);
    /* 50 + 50*sqrt(2) = 120.71, rounded outwards to 121. */
    ck_assert_int_eq(clip.w, 121);

    rgame_canvas_destroy(&c);
}
END_TEST

START_TEST(clip_bounds_round_outwards_so_a_partial_pixel_survives) {
    /*
     * A scale of 1.5 turns a 5-wide clip into 7.5 screen pixels, and the half
     * pixel has to be kept: rounding the far edge down would shave a column off
     * every scaled clip. Every other clip test here lands on whole numbers, so
     * this is the only place the rounding direction is observable at all.
     */
    rgame_canvas c;
    begin(&c);

    rgame_canvas_push_scale(&c, 1.5f, 1.5f);
    rgame_canvas_push_clip(&c, rgame_rect_make(0, 0, 5, 5));
    quad_at(&c, 0.0f, 0.0f, RGAME_COLOR_WHITE, 0.0);
    rgame_canvas_pop(&c);
    rgame_canvas_pop(&c);
    rgame_canvas_end_frame(&c);

    ck_assert_int_eq(batch(&c, 0)->clip.w, 8);
    ck_assert_int_eq(batch(&c, 0)->clip.h, 8);

    rgame_canvas_destroy(&c);
}
END_TEST

START_TEST(a_clip_outside_the_window_drops_the_draw_entirely) {
    rgame_canvas c;
    begin(&c);

    rgame_canvas_push_clip(&c, rgame_rect_make(5000, 5000, 10, 10));
    quad_at(&c, 0.0f, 0.0f, RGAME_COLOR_WHITE, 0.0);
    rgame_canvas_pop(&c);
    rgame_canvas_end_frame(&c);

    ck_assert_uint_eq(batch_count(&c), 0);
    ck_assert_uint_eq(rgame_draw_queue_command_count(rgame_canvas_queue(&c)), 0);

    rgame_canvas_destroy(&c);
}
END_TEST

/* --- one pop for any push --- */

START_TEST(the_same_pop_undoes_a_transform_or_a_clip) {
    rgame_canvas c;
    begin(&c);

    rgame_canvas_push_translate(&c, 10.0f, 0.0f);
    rgame_canvas_push_clip(&c, rgame_rect_make(0, 0, 100, 100));
    rgame_canvas_push_scale(&c, 2.0f, 2.0f);
    ck_assert_int_eq(rgame_canvas_depth(&c), 3);

    rgame_canvas_pop(&c); /* the scale */
    rgame_canvas_pop(&c); /* the clip */

    /* The translate is still in force and the clip is gone. */
    quad_at(&c, 0.0f, 0.0f, RGAME_COLOR_WHITE, 0.0);
    rgame_canvas_pop(&c);
    rgame_canvas_end_frame(&c);

    ck_vertex_xy(&c, 0, 10.0f, 0.0f);
    ck_assert_int_eq(batch(&c, 0)->clip.w, 800);
    ck_assert_int_eq(rgame_canvas_depth(&c), 0);

    rgame_canvas_destroy(&c);
}
END_TEST

START_TEST(pops_stay_paired_with_pushes_past_the_stack_limit) {
    /*
     * Beyond the stack depth a push cannot take effect, but it must still be
     * counted — otherwise the caller's matching pop would unwind somebody
     * else's transform and every later draw would land somewhere wrong. Far
     * more damaging than the draws that simply come out untransformed.
     */
    rgame_canvas c;
    begin(&c);

    const int pushes = RGAME_CANVAS_STACK_DEPTH + 20;
    for (int i = 0; i < pushes; i++) {
        rgame_canvas_push_translate(&c, 1.0f, 0.0f);
    }
    ck_assert_int_eq(rgame_canvas_depth(&c), pushes);

    for (int i = 0; i < pushes; i++) {
        rgame_canvas_pop(&c);
    }
    ck_assert_int_eq(rgame_canvas_depth(&c), 0);

    /* Back to the identity: a balanced frame leaves nothing behind. */
    quad_at(&c, 7.0f, 8.0f, RGAME_COLOR_WHITE, 0.0);
    rgame_canvas_end_frame(&c);
    ck_vertex_xy(&c, 0, 7.0f, 8.0f);

    rgame_canvas_destroy(&c);
}
END_TEST

START_TEST(an_unbalanced_pop_is_harmless) {
    rgame_canvas c;
    begin(&c);

    rgame_canvas_pop(&c);
    rgame_canvas_pop(&c);
    quad_at(&c, 1.0f, 2.0f, RGAME_COLOR_WHITE, 0.0);
    rgame_canvas_end_frame(&c);

    ck_vertex_xy(&c, 0, 1.0f, 2.0f);

    rgame_canvas_destroy(&c);
}
END_TEST

/* --- the frame --- */

START_TEST(z_order_wins_over_draw_order_through_the_canvas) {
    rgame_canvas c;
    begin(&c);

    quad_at(&c, 1.0f, 0.0f, RGAME_COLOR_WHITE, 10.0); /* drawn first, on top */
    quad_at(&c, 2.0f, 0.0f, RGAME_COLOR_WHITE, 1.0);  /* drawn last, behind */
    rgame_canvas_end_frame(&c);

    ck_vertex_xy(&c, 0, 2.0f, 0.0f);
    ck_vertex_xy(&c, 6, 1.0f, 0.0f);

    rgame_canvas_destroy(&c);
}
END_TEST

START_TEST(begin_frame_clears_the_previous_frame_and_its_stacks) {
    rgame_canvas c;
    begin(&c);

    rgame_canvas_push_translate(&c, 500.0f, 500.0f);
    quad_at(&c, 0.0f, 0.0f, RGAME_COLOR_WHITE, 0.0);
    rgame_canvas_end_frame(&c);
    ck_assert_uint_eq(batch_count(&c), 1);

    /* No pop was issued — the next frame must not inherit that translate. */
    rgame_canvas_begin_frame(&c, 800, 600);
    ck_assert_int_eq(rgame_canvas_depth(&c), 0);
    quad_at(&c, 3.0f, 4.0f, RGAME_COLOR_WHITE, 0.0);
    rgame_canvas_end_frame(&c);

    ck_assert_uint_eq(batch_count(&c), 1);
    ck_vertex_xy(&c, 0, 3.0f, 4.0f);

    rgame_canvas_destroy(&c);
}
END_TEST

START_TEST(begin_frame_adopts_a_new_window_size_for_the_base_clip) {
    rgame_canvas c;
    begin(&c);
    rgame_canvas_begin_frame(&c, 1024, 768);

    quad_at(&c, 0.0f, 0.0f, RGAME_COLOR_WHITE, 0.0);
    rgame_canvas_end_frame(&c);

    ck_assert_int_eq(batch(&c, 0)->clip.w, 1024);
    ck_assert_int_eq(batch(&c, 0)->clip.h, 768);

    rgame_canvas_destroy(&c);
}
END_TEST

/* --- split-screen, end to end --- */

START_TEST(two_viewports_each_get_their_own_clip_and_camera) {
    /*
     * The shape split-screen actually takes: for each player, clip to their
     * half of the screen, translate by their camera, and run the *same* world
     * draw. Nothing else is needed — no new primitive, no second renderer.
     *
     * This is the case a single-viewport design gets wrong, because the two
     * halves interleave in the queue after sorting and only survive if each
     * command carried its own clip.
     */
    rgame_canvas c;
    begin(&c);

    /* Player 1: left half, camera at world (1000, 0). */
    rgame_canvas_push_clip(&c, rgame_rect_make(0, 0, 400, 600));
    rgame_canvas_push_translate(&c, -1000.0f, 0.0f);
    quad_at(&c, 1000.0f, 100.0f, RGAME_COLOR_WHITE, 5.0);
    rgame_canvas_pop(&c);
    rgame_canvas_pop(&c);

    /* Player 2: right half, camera at world (2000, 0). Drawn at a lower z, so
     * sorting genuinely interleaves the two viewports. */
    rgame_canvas_push_clip(&c, rgame_rect_make(400, 0, 400, 600));
    rgame_canvas_push_translate(&c, -2000.0f + 400.0f, 0.0f);
    quad_at(&c, 2000.0f, 200.0f, RGAME_COLOR_WHITE, 1.0);
    rgame_canvas_pop(&c);
    rgame_canvas_pop(&c);

    rgame_canvas_end_frame(&c);

    /* Two batches, because the clips differ — and player 2 sorts first. */
    ck_assert_uint_eq(batch_count(&c), 2);
    ck_assert_int_eq(batch(&c, 0)->clip.x, 400);
    ck_assert_int_eq(batch(&c, 1)->clip.x, 0);

    /* Each player's world object lands inside their own viewport. */
    ck_vertex_xy(&c, 0, 400.0f, 200.0f); /* player 2 */
    ck_vertex_xy(&c, 6, 0.0f, 100.0f);   /* player 1 */

    ck_assert_int_eq(rgame_canvas_depth(&c), 0);

    rgame_canvas_destroy(&c);
}
END_TEST

Suite *canvas_suite(void) {
    Suite *suite = suite_create("canvas");

    TCase *tc_prims = tcase_create("primitives");
    tcase_add_test(tc_prims, a_quad_becomes_two_triangles_in_loop_order);
    tcase_add_test(tc_prims, a_triangle_keeps_its_three_points);
    tcase_add_test(tc_prims, the_colour_reaches_the_vertex_in_gl_byte_order);
    tcase_add_test(tc_prims, a_textured_quad_carries_its_texture_and_uvs);
    suite_add_tcase(suite, tc_prims);

    TCase *tc_tx = tcase_create("transforms");
    tcase_add_test(tc_tx, a_quad_drawn_inside_a_translate_lands_translated);
    tcase_add_test(tc_tx, nested_transforms_compose_inner_first);
    tcase_add_test(tc_tx, popping_a_transform_restores_the_previous_one);
    suite_add_tcase(suite, tc_tx);

    TCase *tc_clip = tcase_create("clipping");
    tcase_add_test(tc_clip, a_quad_carries_the_current_clip_into_its_command);
    tcase_add_test(tc_clip, a_clip_pushed_inside_a_translate_moves_with_it);
    tcase_add_test(tc_clip, a_rotated_clip_becomes_its_bounding_box);
    tcase_add_test(tc_clip, clip_bounds_round_outwards_so_a_partial_pixel_survives);
    tcase_add_test(tc_clip, a_clip_outside_the_window_drops_the_draw_entirely);
    suite_add_tcase(suite, tc_clip);

    TCase *tc_stack = tcase_create("push_pop");
    tcase_add_test(tc_stack, the_same_pop_undoes_a_transform_or_a_clip);
    tcase_add_test(tc_stack, pops_stay_paired_with_pushes_past_the_stack_limit);
    tcase_add_test(tc_stack, an_unbalanced_pop_is_harmless);
    suite_add_tcase(suite, tc_stack);

    TCase *tc_frame = tcase_create("frame");
    tcase_add_test(tc_frame, z_order_wins_over_draw_order_through_the_canvas);
    tcase_add_test(tc_frame, begin_frame_clears_the_previous_frame_and_its_stacks);
    tcase_add_test(tc_frame, begin_frame_adopts_a_new_window_size_for_the_base_clip);
    tcase_add_test(tc_frame, two_viewports_each_get_their_own_clip_and_camera);
    suite_add_tcase(suite, tc_frame);

    return suite;
}
