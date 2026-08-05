#include <check.h>
#include <math.h>

#include "graphics/primitives.h"
#include "suites.h"

/*
 * Layer-1 tests for primitives.c: what a rect, line, circle or image actually
 * puts into the draw queue. Read back through the canvas, so the assertions are
 * on coordinates a person can check by hand rather than on GL calls.
 */

#define TOL 1e-3f

static void begin(rgame_canvas *c) {
    rgame_canvas_init(c);
    rgame_canvas_begin_frame(c, 800, 600);
}

static const rgame_draw_queue *queue(const rgame_canvas *c) {
    return rgame_canvas_queue(c);
}

static const rgame_vertex *vertex(const rgame_canvas *c, unsigned int index) {
    return &rgame_draw_queue_vertices(queue(c))[index];
}

static void ck_vertex_xy(const rgame_canvas *c, unsigned int index, float x, float y) {
    ck_assert_float_eq_tol(vertex(c, index)->x, x, TOL);
    ck_assert_float_eq_tol(vertex(c, index)->y, y, TOL);
}

static void ck_vertex_uv(const rgame_canvas *c, unsigned int index, float u, float v) {
    ck_assert_float_eq_tol(vertex(c, index)->u, u, TOL);
    ck_assert_float_eq_tol(vertex(c, index)->v, v, TOL);
}

/* A 64x32 sheet with a memorable GL name, and a whole-sheet view of it. The
 * caller owns the view and must destroy it. */
static rgame_texture test_texture(unsigned int name, int width, int height) {
    rgame_texture_sheet *sheet = rgame_texture_sheet_create(name, width, height);
    rgame_texture view = rgame_texture_whole(sheet);
    rgame_texture_sheet_release(sheet, NULL);
    return view;
}

/* --- rect --- */

START_TEST(a_rect_is_one_quad_at_its_corners) {
    rgame_canvas c;
    begin(&c);

    rgame_prim_rect(&c, 10.0f, 20.0f, 30.0f, 40.0f, RGAME_COLOR_WHITE, 0.0);
    rgame_canvas_end_frame(&c);

    /* Two triangles, 0-1-2 and 0-2-3, from corners in loop order. */
    ck_assert_uint_eq(rgame_draw_queue_vertex_count(queue(&c)), 6);
    ck_vertex_xy(&c, 0, 10.0f, 20.0f); /* top-left */
    ck_vertex_xy(&c, 1, 40.0f, 20.0f); /* top-right */
    ck_vertex_xy(&c, 2, 40.0f, 60.0f); /* bottom-right */
    ck_vertex_xy(&c, 5, 10.0f, 60.0f); /* bottom-left */

    rgame_canvas_destroy(&c);
}
END_TEST

START_TEST(a_rect_is_untextured) {
    rgame_canvas c;
    begin(&c);

    rgame_prim_rect(&c, 0.0f, 0.0f, 10.0f, 10.0f, RGAME_COLOR_WHITE, 0.0);
    rgame_canvas_end_frame(&c);

    /* Texture 0 is what tells the backend to draw flat colour. */
    ck_assert_uint_eq(rgame_draw_queue_batch(queue(&c), 0)->texture, 0);

    rgame_canvas_destroy(&c);
}
END_TEST

/* --- line --- */

START_TEST(a_horizontal_line_is_a_quad_of_the_requested_thickness) {
    rgame_canvas c;
    begin(&c);

    /* From (10,50) to (110,50), 4px thick: a 100x4 band centred on y = 50. */
    rgame_prim_line(&c, 10.0f, 50.0f, 110.0f, 50.0f, 4.0f, RGAME_COLOR_WHITE, 0.0);
    rgame_canvas_end_frame(&c);

    ck_assert_uint_eq(rgame_draw_queue_vertex_count(queue(&c)), 6);
    ck_vertex_xy(&c, 0, 10.0f, 52.0f);
    ck_vertex_xy(&c, 1, 110.0f, 52.0f);
    ck_vertex_xy(&c, 2, 110.0f, 48.0f);
    ck_vertex_xy(&c, 5, 10.0f, 48.0f);

    rgame_canvas_destroy(&c);
}
END_TEST

START_TEST(a_vertical_line_is_thick_across_x) {
    /* The axis the offset lands on is the whole point: getting dx and dy the
     * wrong way round makes a vertical line thick vertically, which is to say
     * invisible. */
    rgame_canvas c;
    begin(&c);

    rgame_prim_line(&c, 50.0f, 10.0f, 50.0f, 110.0f, 6.0f, RGAME_COLOR_WHITE, 0.0);
    rgame_canvas_end_frame(&c);

    ck_vertex_xy(&c, 0, 47.0f, 10.0f);
    ck_vertex_xy(&c, 1, 47.0f, 110.0f);
    ck_vertex_xy(&c, 2, 53.0f, 110.0f);
    ck_vertex_xy(&c, 5, 53.0f, 10.0f);

    rgame_canvas_destroy(&c);
}
END_TEST

START_TEST(a_diagonal_lines_corners_stay_half_a_thickness_from_its_axis) {
    rgame_canvas c;
    begin(&c);

    /* A 3-4-5 diagonal, 10 thick: each corner is 5 from the centre line, and
     * the quad's short edge is exactly the thickness. */
    rgame_prim_line(&c, 0.0f, 0.0f, 30.0f, 40.0f, 10.0f, RGAME_COLOR_WHITE, 0.0);
    rgame_canvas_end_frame(&c);

    const rgame_vertex *start_a = vertex(&c, 0);
    const rgame_vertex *start_b = vertex(&c, 5);
    float edge = sqrtf(powf(start_a->x - start_b->x, 2.0f) + powf(start_a->y - start_b->y, 2.0f));

    ck_assert_float_eq_tol(edge, 10.0f, TOL);
    /* And the corners straddle the start point rather than sitting past it. */
    ck_assert_float_eq_tol((start_a->x + start_b->x) / 2.0f, 0.0f, TOL);
    ck_assert_float_eq_tol((start_a->y + start_b->y) / 2.0f, 0.0f, TOL);

    rgame_canvas_destroy(&c);
}
END_TEST

START_TEST(a_zero_length_line_draws_nothing) {
    /* Rather than dividing by its own length. */
    rgame_canvas c;
    begin(&c);

    rgame_prim_line(&c, 5.0f, 5.0f, 5.0f, 5.0f, 2.0f, RGAME_COLOR_WHITE, 0.0);
    rgame_canvas_end_frame(&c);

    ck_assert_uint_eq(rgame_draw_queue_vertex_count(queue(&c)), 0);

    rgame_canvas_destroy(&c);
}
END_TEST

/* --- circle --- */

START_TEST(a_circle_is_a_fan_of_the_requested_segment_count) {
    rgame_canvas c;
    begin(&c);

    rgame_prim_circle(&c, 100.0f, 100.0f, 20.0f, 8, RGAME_COLOR_WHITE, 0.0);
    rgame_canvas_end_frame(&c);

    ck_assert_uint_eq(rgame_draw_queue_vertex_count(queue(&c)), 8 * 3);
    /* Same texture, same clip, same z — so the whole fan is one batch, which is
     * what makes a per-call fan cheaper than the cached texture it replaced. */
    ck_assert_uint_eq(rgame_draw_queue_batch_count(queue(&c)), 1);

    rgame_canvas_destroy(&c);
}
END_TEST

START_TEST(every_circle_vertex_is_at_the_centre_or_on_the_radius) {
    rgame_canvas c;
    begin(&c);

    rgame_prim_circle(&c, 100.0f, 50.0f, 20.0f, 16, RGAME_COLOR_WHITE, 0.0);
    rgame_canvas_end_frame(&c);

    for (unsigned int i = 0; i < rgame_draw_queue_vertex_count(queue(&c)); i++) {
        const rgame_vertex *v = vertex(&c, i);
        float distance = sqrtf(powf(v->x - 100.0f, 2.0f) + powf(v->y - 50.0f, 2.0f));

        /* Every third vertex is the centre; the other two are on the rim. */
        if (i % 3 == 0) {
            ck_assert_float_eq_tol(distance, 0.0f, TOL);
        } else {
            ck_assert_float_eq_tol(distance, 20.0f, TOL);
        }
    }

    rgame_canvas_destroy(&c);
}
END_TEST

START_TEST(the_circle_fan_closes) {
    /* The last wedge has to end where the first began. Accumulating the angle
     * instead of computing it leaves a hairline gap that only shows on large
     * circles. */
    rgame_canvas c;
    begin(&c);

    rgame_prim_circle(&c, 0.0f, 0.0f, 10.0f, 12, RGAME_COLOR_WHITE, 0.0);
    rgame_canvas_end_frame(&c);

    unsigned int last = rgame_draw_queue_vertex_count(queue(&c)) - 1;
    ck_assert_float_eq_tol(vertex(&c, last)->x, vertex(&c, 1)->x, TOL);
    ck_assert_float_eq_tol(vertex(&c, last)->y, vertex(&c, 1)->y, TOL);

    rgame_canvas_destroy(&c);
}
END_TEST

START_TEST(a_degenerate_circle_draws_nothing) {
    rgame_canvas c;
    begin(&c);

    rgame_prim_circle(&c, 0.0f, 0.0f, 10.0f, 2, RGAME_COLOR_WHITE, 0.0);
    rgame_prim_circle(&c, 0.0f, 0.0f, 0.0f, 32, RGAME_COLOR_WHITE, 0.0);
    rgame_prim_circle(&c, 0.0f, 0.0f, -5.0f, 32, RGAME_COLOR_WHITE, 0.0);
    rgame_canvas_end_frame(&c);

    ck_assert_uint_eq(rgame_draw_queue_vertex_count(queue(&c)), 0);

    rgame_canvas_destroy(&c);
}
END_TEST

/* --- images --- */

START_TEST(an_image_is_placed_by_its_top_left_at_its_natural_size) {
    rgame_canvas c;
    begin(&c);
    rgame_texture view = test_texture(7, 64, 32);

    rgame_prim_image(&c, &view, 10.0f, 20.0f, RGAME_COLOR_WHITE, 0.0);
    rgame_canvas_end_frame(&c);

    ck_vertex_xy(&c, 0, 10.0f, 20.0f);
    ck_vertex_xy(&c, 1, 74.0f, 20.0f);
    ck_vertex_xy(&c, 2, 74.0f, 52.0f);
    /* And it carries the sheet's GL name, so the backend binds the right one. */
    ck_assert_uint_eq(rgame_draw_queue_batch(queue(&c), 0)->texture, 7);

    rgame_texture_destroy(&view, NULL);
    rgame_canvas_destroy(&c);
}
END_TEST

START_TEST(an_images_uvs_match_its_corners) {
    rgame_canvas c;
    begin(&c);
    rgame_texture sheet = test_texture(7, 64, 64);
    rgame_texture tile = {0};
    /* The bottom-right quarter of the sheet: u and v both 0.5..1. */
    rgame_texture_subimage(&sheet, 32, 32, 32, 32, &tile);

    rgame_prim_image(&c, &tile, 0.0f, 0.0f, RGAME_COLOR_WHITE, 0.0);
    rgame_canvas_end_frame(&c);

    ck_vertex_uv(&c, 0, 0.5f, 0.5f); /* top-left corner of the quad */
    ck_vertex_uv(&c, 1, 1.0f, 0.5f); /* top-right */
    ck_vertex_uv(&c, 2, 1.0f, 1.0f); /* bottom-right */
    ck_vertex_uv(&c, 5, 0.5f, 1.0f); /* bottom-left */

    rgame_texture_destroy(&tile, NULL);
    rgame_texture_destroy(&sheet, NULL);
    rgame_canvas_destroy(&c);
}
END_TEST

START_TEST(a_rotated_image_is_centred_on_its_position) {
    rgame_canvas c;
    begin(&c);
    rgame_texture view = test_texture(7, 20, 10);

    rgame_prim_image_rot(&c, &view, 100.0f, 100.0f, 0.0f, 1.0f, RGAME_COLOR_WHITE, 0.0);
    rgame_canvas_end_frame(&c);

    /* Half the width left and right of 100, half the height above and below. */
    ck_vertex_xy(&c, 0, 90.0f, 95.0f);
    ck_vertex_xy(&c, 2, 110.0f, 105.0f);

    rgame_texture_destroy(&view, NULL);
    rgame_canvas_destroy(&c);
}
END_TEST

START_TEST(a_scaled_image_grows_about_its_centre) {
    rgame_canvas c;
    begin(&c);
    rgame_texture view = test_texture(7, 20, 10);

    rgame_prim_image_rot(&c, &view, 100.0f, 100.0f, 0.0f, 2.0f, RGAME_COLOR_WHITE, 0.0);
    rgame_canvas_end_frame(&c);

    ck_vertex_xy(&c, 0, 80.0f, 90.0f);
    ck_vertex_xy(&c, 2, 120.0f, 110.0f);

    rgame_texture_destroy(&view, NULL);
    rgame_canvas_destroy(&c);
}
END_TEST

START_TEST(a_positive_angle_turns_an_image_clockwise) {
    /* The convention measured against the layer being replaced: a positive
     * angle moves a point that was to the right of the pivot *downwards*,
     * because screen y points down. Asserted on a coordinate rather than a
     * matrix entry — a matrix test passes just as happily backwards.
     */
    rgame_canvas c;
    begin(&c);
    rgame_texture view = test_texture(7, 20, 10);

    rgame_prim_image_rot(&c, &view, 100.0f, 100.0f, 90.0f, 1.0f, RGAME_COLOR_WHITE, 0.0);
    rgame_canvas_end_frame(&c);

    /* The top-left corner (90, 95) rotated 90 degrees clockwise about (100,100)
     * lands at (105, 90). */
    ck_vertex_xy(&c, 0, 105.0f, 90.0f);

    rgame_texture_destroy(&view, NULL);
    rgame_canvas_destroy(&c);
}
END_TEST

START_TEST(a_rotated_image_leaves_the_stack_where_it_found_it) {
    /* Three pushes and three pops per sprite: one missed pop and every later
     * draw in the frame is displaced, which is a bug that looks like anything
     * except its cause. */
    rgame_canvas c;
    begin(&c);
    rgame_texture view = test_texture(7, 20, 10);

    rgame_canvas_push_translate(&c, 5.0f, 5.0f);
    int depth_before = rgame_canvas_depth(&c);

    rgame_prim_image_rot(&c, &view, 0.0f, 0.0f, 45.0f, 2.0f, RGAME_COLOR_WHITE, 0.0);

    ck_assert_int_eq(rgame_canvas_depth(&c), depth_before);

    rgame_texture_destroy(&view, NULL);
    rgame_canvas_destroy(&c);
}
END_TEST

START_TEST(a_rotated_image_composes_with_the_transform_already_in_place) {
    rgame_canvas c;
    begin(&c);
    rgame_texture view = test_texture(7, 20, 10);

    rgame_canvas_push_translate(&c, 50.0f, 0.0f);
    rgame_prim_image_rot(&c, &view, 100.0f, 100.0f, 0.0f, 2.0f, RGAME_COLOR_WHITE, 0.0);
    rgame_canvas_pop(&c);
    rgame_canvas_end_frame(&c);

    /* The camera's translate applies on top of the sprite's own scale. */
    ck_vertex_xy(&c, 0, 130.0f, 90.0f);

    rgame_texture_destroy(&view, NULL);
    rgame_canvas_destroy(&c);
}
END_TEST

START_TEST(an_image_with_no_texture_draws_nothing) {
    rgame_canvas c;
    begin(&c);
    rgame_texture empty = {0};

    rgame_prim_image(&c, &empty, 0.0f, 0.0f, RGAME_COLOR_WHITE, 0.0);
    rgame_prim_image_rot(&c, &empty, 0.0f, 0.0f, 30.0f, 2.0f, RGAME_COLOR_WHITE, 0.0);
    rgame_prim_image(&c, NULL, 0.0f, 0.0f, RGAME_COLOR_WHITE, 0.0);
    rgame_canvas_end_frame(&c);

    ck_assert_uint_eq(rgame_draw_queue_vertex_count(queue(&c)), 0);
    /* And the rotated path did not leave its pushes behind on the way out. */
    ck_assert_int_eq(rgame_canvas_depth(&c), 0);

    rgame_canvas_destroy(&c);
}
END_TEST

/* --- glyphs --- */

START_TEST(a_glyph_is_drawn_at_its_own_size_from_a_page_rect) {
    rgame_canvas c;
    begin(&c);

    /* A 12x16 glyph living at 32,48 on a 128x128 page, drawn at 100,200. */
    rgame_prim_glyph(&c, 5, rgame_rect_make(32, 48, 12, 16), 128, 128, 100.0f, 200.0f,
                     RGAME_COLOR_WHITE, 0.0);
    rgame_canvas_end_frame(&c);

    ck_vertex_xy(&c, 0, 100.0f, 200.0f);
    ck_vertex_xy(&c, 1, 112.0f, 200.0f);
    ck_vertex_xy(&c, 2, 112.0f, 216.0f);
    ck_assert_uint_eq(rgame_draw_queue_batch(queue(&c), 0)->texture, 5);

    rgame_canvas_destroy(&c);
}
END_TEST

START_TEST(a_glyphs_uvs_are_normalised_against_the_page) {
    /* The same mistake rgame_texture_uv exists to prevent, in the other place
     * it could be made: dividing by the glyph rather than the page would
     * stretch every letter across the whole atlas. */
    rgame_canvas c;
    begin(&c);

    rgame_prim_glyph(&c, 5, rgame_rect_make(32, 48, 32, 32), 128, 128, 0.0f, 0.0f,
                     RGAME_COLOR_WHITE, 0.0);
    rgame_canvas_end_frame(&c);

    ck_vertex_uv(&c, 0, 0.25f, 0.375f);
    ck_vertex_uv(&c, 2, 0.5f, 0.625f);

    rgame_canvas_destroy(&c);
}
END_TEST

START_TEST(a_glyph_with_no_pixels_draws_nothing) {
    /* A space reaches here like any other glyph. */
    rgame_canvas c;
    begin(&c);

    rgame_prim_glyph(&c, 5, rgame_rect_make(0, 0, 0, 0), 128, 128, 0.0f, 0.0f,
                     RGAME_COLOR_WHITE, 0.0);
    rgame_prim_glyph(&c, 5, rgame_rect_make(0, 0, 4, 4), 0, 0, 0.0f, 0.0f, RGAME_COLOR_WHITE,
                     0.0);
    rgame_canvas_end_frame(&c);

    ck_assert_uint_eq(rgame_draw_queue_vertex_count(queue(&c)), 0);

    rgame_canvas_destroy(&c);
}
END_TEST

Suite *primitives_suite(void) {
    Suite *suite = suite_create("primitives");
    TCase *tc = tcase_create("core");

    tcase_add_test(tc, a_rect_is_one_quad_at_its_corners);
    tcase_add_test(tc, a_rect_is_untextured);

    tcase_add_test(tc, a_horizontal_line_is_a_quad_of_the_requested_thickness);
    tcase_add_test(tc, a_vertical_line_is_thick_across_x);
    tcase_add_test(tc, a_diagonal_lines_corners_stay_half_a_thickness_from_its_axis);
    tcase_add_test(tc, a_zero_length_line_draws_nothing);

    tcase_add_test(tc, a_circle_is_a_fan_of_the_requested_segment_count);
    tcase_add_test(tc, every_circle_vertex_is_at_the_centre_or_on_the_radius);
    tcase_add_test(tc, the_circle_fan_closes);
    tcase_add_test(tc, a_degenerate_circle_draws_nothing);

    tcase_add_test(tc, an_image_is_placed_by_its_top_left_at_its_natural_size);
    tcase_add_test(tc, an_images_uvs_match_its_corners);
    tcase_add_test(tc, a_rotated_image_is_centred_on_its_position);
    tcase_add_test(tc, a_scaled_image_grows_about_its_centre);
    tcase_add_test(tc, a_positive_angle_turns_an_image_clockwise);
    tcase_add_test(tc, a_rotated_image_leaves_the_stack_where_it_found_it);
    tcase_add_test(tc, a_rotated_image_composes_with_the_transform_already_in_place);
    tcase_add_test(tc, an_image_with_no_texture_draws_nothing);

    tcase_add_test(tc, a_glyph_is_drawn_at_its_own_size_from_a_page_rect);
    tcase_add_test(tc, a_glyphs_uvs_are_normalised_against_the_page);
    tcase_add_test(tc, a_glyph_with_no_pixels_draws_nothing);

    suite_add_tcase(suite, tc);
    return suite;
}
