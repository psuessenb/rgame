#include <check.h>
#include <limits.h>

#include "graphics/clip.h"
#include "suites.h"

static void ck_rect(rgame_rect got, int x, int y, int w, int h) {
    ck_assert_int_eq(got.x, x);
    ck_assert_int_eq(got.y, y);
    ck_assert_int_eq(got.w, w);
    ck_assert_int_eq(got.h, h);
}

/* --- rect arithmetic --- */

START_TEST(overlapping_rects_intersect_to_the_shared_area) {
    rgame_rect a = rgame_rect_make(0, 0, 100, 100);
    rgame_rect b = rgame_rect_make(50, 50, 100, 100);

    ck_rect(rgame_rect_intersect(a, b), 50, 50, 50, 50);
    /* Intersection is symmetric; a batch key must not depend on argument order. */
    ck_rect(rgame_rect_intersect(b, a), 50, 50, 50, 50);
}
END_TEST

START_TEST(a_contained_rect_intersects_to_itself) {
    rgame_rect outer = rgame_rect_make(0, 0, 100, 100);
    rgame_rect inner = rgame_rect_make(10, 20, 30, 40);

    ck_rect(rgame_rect_intersect(outer, inner), 10, 20, 30, 40);
}
END_TEST

START_TEST(disjoint_rects_intersect_to_nothing) {
    rgame_rect a = rgame_rect_make(0, 0, 10, 10);
    rgame_rect b = rgame_rect_make(50, 50, 10, 10);

    ck_assert_int_eq(rgame_rect_is_empty(rgame_rect_intersect(a, b)), 1);
}
END_TEST

START_TEST(rects_that_merely_touch_do_not_overlap) {
    /* Edges are half-open: a rect at x 0..10 and one at x 10..20 share a
     * boundary but no pixel. Getting this wrong paints a one-pixel seam. */
    rgame_rect a = rgame_rect_make(0, 0, 10, 10);
    rgame_rect b = rgame_rect_make(10, 0, 10, 10);

    ck_assert_int_eq(rgame_rect_is_empty(rgame_rect_intersect(a, b)), 1);
}
END_TEST

START_TEST(every_empty_result_is_the_same_empty) {
    /*
     * The draw queue uses the clip rect as part of its batch key, so two
     * different routes to "nothing" must compare equal rather than splitting a
     * batch — or, worse, being told apart when they should not be.
     */
    rgame_rect far_apart = rgame_rect_intersect(rgame_rect_make(0, 0, 5, 5),
                                                rgame_rect_make(900, 900, 5, 5));
    rgame_rect touching = rgame_rect_intersect(rgame_rect_make(0, 0, 10, 10),
                                               rgame_rect_make(10, 0, 10, 10));
    rgame_rect degenerate = rgame_rect_make(3, 4, 0, 50);

    ck_assert_int_eq(rgame_rect_equals(far_apart, touching), 1);
    ck_assert_int_eq(rgame_rect_equals(far_apart, degenerate), 1);
    ck_rect(far_apart, 0, 0, 0, 0);
}
END_TEST

START_TEST(a_zero_or_negative_size_rect_is_empty_from_the_start) {
    ck_assert_int_eq(rgame_rect_is_empty(rgame_rect_make(0, 0, 0, 10)), 1);
    ck_assert_int_eq(rgame_rect_is_empty(rgame_rect_make(0, 0, 10, 0)), 1);
    ck_assert_int_eq(rgame_rect_is_empty(rgame_rect_make(0, 0, -5, 10)), 1);
    ck_assert_int_eq(rgame_rect_is_empty(rgame_rect_make(0, 0, 1, 1)), 0);
}
END_TEST

START_TEST(intersecting_with_an_empty_rect_yields_empty) {
    rgame_rect real = rgame_rect_make(0, 0, 100, 100);
    rgame_rect empty = rgame_rect_make(0, 0, 0, 0);

    ck_assert_int_eq(rgame_rect_is_empty(rgame_rect_intersect(real, empty)), 1);
    ck_assert_int_eq(rgame_rect_is_empty(rgame_rect_intersect(empty, real)), 1);
}
END_TEST

/*
 * The next two build rects as raw struct literals rather than through
 * rgame_rect_make, deliberately. rect_make canonicalises an empty rect to
 * {0,0,0,0} on the way in, so going through it would never exercise what
 * is_empty and intersect do with a *non-canonical* empty — which a caller
 * assembling a rect by hand, or the canvas building one from transformed
 * corners, can perfectly well hand them.
 */

START_TEST(is_empty_checks_both_dimensions) {
    rgame_rect zero_height = { 0, 0, 10, 0 };
    rgame_rect zero_width = { 0, 0, 0, 10 };
    rgame_rect negative_height = { 0, 0, 10, -3 };

    ck_assert_int_eq(rgame_rect_is_empty(zero_height), 1);
    ck_assert_int_eq(rgame_rect_is_empty(zero_width), 1);
    ck_assert_int_eq(rgame_rect_is_empty(negative_height), 1);
}
END_TEST

START_TEST(an_empty_input_is_canonicalised_on_the_way_out) {
    /* An empty rect carrying a non-zero position must still intersect to the
     * canonical empty, or two "nothing"s would compare unequal and split a
     * batch that should never have been drawn at all. */
    rgame_rect positioned_empty = { 37, 41, 0, 12 };
    rgame_rect real = rgame_rect_make(0, 0, 100, 100);

    ck_rect(rgame_rect_intersect(real, positioned_empty), 0, 0, 0, 0);
    ck_rect(rgame_rect_intersect(positioned_empty, real), 0, 0, 0, 0);
}
END_TEST

START_TEST(a_huge_rect_does_not_overflow_the_edge_arithmetic) {
    /*
     * "As wide as possible" is a legitimate thing for a caller to mean, and
     * x + w would overflow int — undefined behaviour, not just a wrong answer.
     * The sanitizer build is what actually catches a regression here.
     */
    rgame_rect huge = rgame_rect_make(0, 0, INT_MAX, INT_MAX);
    rgame_rect window = rgame_rect_make(0, 0, 800, 600);

    ck_rect(rgame_rect_intersect(huge, window), 0, 0, 800, 600);

    rgame_rect far = rgame_rect_make(INT_MAX - 10, INT_MAX - 10, 100, 100);
    ck_assert_int_eq(rgame_rect_is_empty(rgame_rect_intersect(far, window)), 1);
}
END_TEST

START_TEST(negative_coordinates_intersect_normally) {
    /* A camera can push content to negative screen coordinates. */
    rgame_rect a = rgame_rect_make(-50, -50, 100, 100);
    rgame_rect b = rgame_rect_make(0, 0, 100, 100);

    ck_rect(rgame_rect_intersect(a, b), 0, 0, 50, 50);
}
END_TEST

START_TEST(contains_point_uses_the_same_half_open_edges) {
    rgame_rect r = rgame_rect_make(10, 10, 5, 5);

    ck_assert_int_eq(rgame_rect_contains_point(r, 10, 10), 1);
    ck_assert_int_eq(rgame_rect_contains_point(r, 14, 14), 1);
    ck_assert_int_eq(rgame_rect_contains_point(r, 15, 14), 0); /* right edge excluded */
    ck_assert_int_eq(rgame_rect_contains_point(r, 9, 10), 0);
    ck_assert_int_eq(rgame_rect_contains_point(rgame_rect_make(0, 0, 0, 0), 0, 0), 0);
}
END_TEST

/* --- the stack --- */

START_TEST(a_fresh_stack_clips_to_the_window) {
    /* The base is the window rather than "no clip", so every command carries a
     * meaningful rect and there is no null case anywhere downstream. */
    rgame_clip_stack s;
    rgame_clip_stack_init(&s, 800, 600);

    ck_rect(rgame_clip_current(&s), 0, 0, 800, 600);
    ck_assert_int_eq(rgame_clip_is_empty(&s), 0);
    ck_assert_int_eq(rgame_clip_depth(&s), 0);
}
END_TEST

START_TEST(pushing_narrows_the_clip) {
    rgame_clip_stack s;
    rgame_clip_stack_init(&s, 800, 600);
    ck_assert_int_eq(rgame_clip_push(&s, rgame_rect_make(100, 100, 200, 200)), 1);

    ck_rect(rgame_clip_current(&s), 100, 100, 200, 200);
}
END_TEST

START_TEST(a_push_intersects_rather_than_replaces) {
    /* The property the whole stack exists for: a child cannot draw outside the
     * region its parent allowed, however large a rect it asks for. */
    rgame_clip_stack s;
    rgame_clip_stack_init(&s, 800, 600);
    rgame_clip_push(&s, rgame_rect_make(100, 100, 100, 100));
    rgame_clip_push(&s, rgame_rect_make(0, 0, 800, 600));

    ck_rect(rgame_clip_current(&s), 100, 100, 100, 100);
}
END_TEST

START_TEST(nested_pushes_intersect_cumulatively) {
    rgame_clip_stack s;
    rgame_clip_stack_init(&s, 800, 600);
    rgame_clip_push(&s, rgame_rect_make(0, 0, 400, 400));
    rgame_clip_push(&s, rgame_rect_make(200, 0, 400, 400));
    rgame_clip_push(&s, rgame_rect_make(0, 100, 800, 100));

    ck_rect(rgame_clip_current(&s), 200, 100, 200, 100);
}
END_TEST

START_TEST(a_push_outside_the_window_clips_everything_away) {
    rgame_clip_stack s;
    rgame_clip_stack_init(&s, 800, 600);
    rgame_clip_push(&s, rgame_rect_make(2000, 2000, 10, 10));

    ck_assert_int_eq(rgame_clip_is_empty(&s), 1);
}
END_TEST

START_TEST(once_empty_a_deeper_push_stays_empty) {
    /* Narrowing is monotonic: nothing nested inside an empty region can
     * resurrect drawing. */
    rgame_clip_stack s;
    rgame_clip_stack_init(&s, 800, 600);
    rgame_clip_push(&s, rgame_rect_make(2000, 2000, 10, 10));
    rgame_clip_push(&s, rgame_rect_make(0, 0, 800, 600));

    ck_assert_int_eq(rgame_clip_is_empty(&s), 1);
}
END_TEST

START_TEST(pop_restores_the_previous_clip_exactly) {
    rgame_clip_stack s;
    rgame_clip_stack_init(&s, 800, 600);
    rgame_clip_push(&s, rgame_rect_make(100, 100, 200, 200));
    rgame_clip_push(&s, rgame_rect_make(150, 150, 10, 10));
    rgame_clip_pop(&s);

    ck_rect(rgame_clip_current(&s), 100, 100, 200, 200);
    ck_assert_int_eq(rgame_clip_depth(&s), 1);
}
END_TEST

START_TEST(popping_back_to_the_base_restores_the_window) {
    rgame_clip_stack s;
    rgame_clip_stack_init(&s, 800, 600);
    rgame_clip_push(&s, rgame_rect_make(1, 2, 3, 4));
    rgame_clip_pop(&s);

    ck_rect(rgame_clip_current(&s), 0, 0, 800, 600);
}
END_TEST

START_TEST(popping_an_empty_stack_is_harmless) {
    rgame_clip_stack s;
    rgame_clip_stack_init(&s, 800, 600);
    rgame_clip_pop(&s);
    rgame_clip_pop(&s);

    ck_assert_int_eq(rgame_clip_depth(&s), 0);
    ck_rect(rgame_clip_current(&s), 0, 0, 800, 600);
}
END_TEST

START_TEST(overflowing_the_stack_is_reported_and_changes_nothing) {
    rgame_clip_stack s;
    rgame_clip_stack_init(&s, 800, 600);

    int pushed = 0;
    while (rgame_clip_push(&s, rgame_rect_make(0, 0, 800, 600))) {
        pushed++;
        ck_assert_int_lt(pushed, RGAME_CLIP_STACK_DEPTH + 1);
    }

    ck_assert_int_eq(rgame_clip_depth(&s), pushed);
    ck_rect(rgame_clip_current(&s), 0, 0, 800, 600);
}
END_TEST

START_TEST(re_initialising_adopts_a_new_window_size) {
    /* How a resize takes effect: the canvas re-inits each frame, so there is no
     * separate "the window changed" path anyone has to remember to call. */
    rgame_clip_stack s;
    rgame_clip_stack_init(&s, 800, 600);
    rgame_clip_push(&s, rgame_rect_make(0, 0, 10, 10));

    rgame_clip_stack_init(&s, 1024, 768);

    ck_assert_int_eq(rgame_clip_depth(&s), 0);
    ck_rect(rgame_clip_current(&s), 0, 0, 1024, 768);
}
END_TEST

/* --- the shape split-screen needs --- */

START_TEST(two_viewports_clip_independently) {
    /*
     * Split-screen in miniature: push one player's region, draw, pop, push the
     * other's. The second must not inherit anything from the first — that is
     * the whole reason this is a stack rather than one current region.
     */
    rgame_clip_stack s;
    rgame_clip_stack_init(&s, 800, 600);

    rgame_clip_push(&s, rgame_rect_make(0, 0, 400, 600));
    ck_rect(rgame_clip_current(&s), 0, 0, 400, 600);
    rgame_clip_pop(&s);

    rgame_clip_push(&s, rgame_rect_make(400, 0, 400, 600));
    ck_rect(rgame_clip_current(&s), 400, 0, 400, 600);
    rgame_clip_pop(&s);

    /* And the frame ends back where it started. */
    ck_rect(rgame_clip_current(&s), 0, 0, 800, 600);
}
END_TEST

Suite *clip_suite(void) {
    Suite *suite = suite_create("clip");

    TCase *tc_rect = tcase_create("rect");
    tcase_add_test(tc_rect, overlapping_rects_intersect_to_the_shared_area);
    tcase_add_test(tc_rect, a_contained_rect_intersects_to_itself);
    tcase_add_test(tc_rect, disjoint_rects_intersect_to_nothing);
    tcase_add_test(tc_rect, rects_that_merely_touch_do_not_overlap);
    tcase_add_test(tc_rect, every_empty_result_is_the_same_empty);
    tcase_add_test(tc_rect, a_zero_or_negative_size_rect_is_empty_from_the_start);
    tcase_add_test(tc_rect, intersecting_with_an_empty_rect_yields_empty);
    tcase_add_test(tc_rect, is_empty_checks_both_dimensions);
    tcase_add_test(tc_rect, an_empty_input_is_canonicalised_on_the_way_out);
    tcase_add_test(tc_rect, a_huge_rect_does_not_overflow_the_edge_arithmetic);
    tcase_add_test(tc_rect, negative_coordinates_intersect_normally);
    tcase_add_test(tc_rect, contains_point_uses_the_same_half_open_edges);
    suite_add_tcase(suite, tc_rect);

    TCase *tc_stack = tcase_create("stack");
    tcase_add_test(tc_stack, a_fresh_stack_clips_to_the_window);
    tcase_add_test(tc_stack, pushing_narrows_the_clip);
    tcase_add_test(tc_stack, a_push_intersects_rather_than_replaces);
    tcase_add_test(tc_stack, nested_pushes_intersect_cumulatively);
    tcase_add_test(tc_stack, a_push_outside_the_window_clips_everything_away);
    tcase_add_test(tc_stack, once_empty_a_deeper_push_stays_empty);
    tcase_add_test(tc_stack, pop_restores_the_previous_clip_exactly);
    tcase_add_test(tc_stack, popping_back_to_the_base_restores_the_window);
    tcase_add_test(tc_stack, popping_an_empty_stack_is_harmless);
    tcase_add_test(tc_stack, overflowing_the_stack_is_reported_and_changes_nothing);
    tcase_add_test(tc_stack, re_initialising_adopts_a_new_window_size);
    tcase_add_test(tc_stack, two_viewports_clip_independently);
    suite_add_tcase(suite, tc_stack);

    return suite;
}
