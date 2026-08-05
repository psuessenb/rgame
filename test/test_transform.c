#include <check.h>

#include "suites.h"
#include "graphics/transform.h"

/*
 * Everything here asserts on *coordinates*, never on matrix entries. A matrix
 * assertion would pass just as happily with the rotation going the wrong way;
 * "the point ends up here" is the property that actually matters, and the one
 * a reader can check against intuition.
 */

#define TOL 1e-4f

static void map(const rgame_transform_stack *s, float x, float y, float *ox, float *oy) {
    rgame_transform_apply(s, x, y, ox, oy);
}

static void ck_point(const rgame_transform_stack *s, float x, float y,
                     float want_x, float want_y) {
    float gx, gy;
    map(s, x, y, &gx, &gy);
    ck_assert_float_eq_tol(gx, want_x, TOL);
    ck_assert_float_eq_tol(gy, want_y, TOL);
}

/* --- the base --- */

START_TEST(a_fresh_stack_leaves_points_alone) {
    rgame_transform_stack s;
    rgame_transform_stack_init(&s);

    ck_point(&s, 0.0f, 0.0f, 0.0f, 0.0f);
    ck_point(&s, 12.5f, -3.0f, 12.5f, -3.0f);
    ck_assert_int_eq(rgame_transform_depth(&s), 0);
    ck_assert_int_eq(rgame_transform_is_identity(&s), 1);
}
END_TEST

/* --- the individual operations --- */

START_TEST(translate_moves_a_point_by_the_offset) {
    rgame_transform_stack s;
    rgame_transform_stack_init(&s);
    ck_assert_int_eq(rgame_transform_push_translate(&s, 10.0f, -4.0f), 1);

    ck_point(&s, 0.0f, 0.0f, 10.0f, -4.0f);
    ck_point(&s, 1.0f, 1.0f, 11.0f, -3.0f);
    ck_assert_int_eq(rgame_transform_is_identity(&s), 0);
}
END_TEST

START_TEST(scale_multiplies_each_axis_independently) {
    rgame_transform_stack s;
    rgame_transform_stack_init(&s);
    rgame_transform_push_scale(&s, 2.0f, 3.0f);

    ck_point(&s, 4.0f, 5.0f, 8.0f, 15.0f);
    /* Scale is about the origin, so the origin does not move. */
    ck_point(&s, 0.0f, 0.0f, 0.0f, 0.0f);
}
END_TEST

START_TEST(a_negative_scale_mirrors_which_is_how_flip_x_works) {
    rgame_transform_stack s;
    rgame_transform_stack_init(&s);
    rgame_transform_push_scale(&s, -1.0f, 1.0f);

    ck_point(&s, 3.0f, 7.0f, -3.0f, 7.0f);
}
END_TEST

/* --- rotation: direction, pivot, units --- */

START_TEST(a_positive_angle_turns_clockwise_on_screen) {
    /*
     * The measured Gosu behaviour, pinned: with y pointing down, a point to the
     * RIGHT of the pivot ends up BELOW it after +90 degrees.
     *
     * Confirmed against Gosu itself by rendering Gosu.rotate(90, 50, 50) with a
     * mark right of the pivot and reading back which pixel was inked. Get this
     * backwards and every rotated sprite in the game mirrors.
     */
    rgame_transform_stack s;
    rgame_transform_stack_init(&s);
    rgame_transform_push_rotate(&s, 90.0f, 0.0f, 0.0f);

    ck_point(&s, 1.0f, 0.0f, 0.0f, 1.0f);   /* right -> below  */
    ck_point(&s, 0.0f, 1.0f, -1.0f, 0.0f);  /* below -> left   */
    ck_point(&s, -1.0f, 0.0f, 0.0f, -1.0f); /* left  -> above  */
}
END_TEST

START_TEST(rotating_about_a_pivot_leaves_the_pivot_fixed) {
    rgame_transform_stack s;
    rgame_transform_stack_init(&s);
    rgame_transform_push_rotate(&s, 37.0f, 100.0f, 50.0f);

    ck_point(&s, 100.0f, 50.0f, 100.0f, 50.0f);
}
END_TEST

START_TEST(rotating_about_a_pivot_swings_the_surrounding_points) {
    /* The same clockwise claim, expressed the way a caller uses it: a mark
     * offset from a node's origin swings around that origin. */
    rgame_transform_stack s;
    rgame_transform_stack_init(&s);
    rgame_transform_push_rotate(&s, 90.0f, 50.0f, 50.0f);

    ck_point(&s, 62.0f, 50.0f, 50.0f, 62.0f); /* right of pivot -> below it */
    ck_point(&s, 50.0f, 62.0f, 38.0f, 50.0f); /* below pivot    -> left of it */
}
END_TEST

START_TEST(angles_are_degrees_not_radians) {
    /* 180 degrees is a half turn. If the argument were taken as radians, 180
     * would be ~29 full turns and land somewhere arbitrary. */
    rgame_transform_stack s;
    rgame_transform_stack_init(&s);
    rgame_transform_push_rotate(&s, 180.0f, 0.0f, 0.0f);
    ck_point(&s, 1.0f, 0.0f, -1.0f, 0.0f);

    /* And a radian-sized number is a tiny rotation, not a half turn. */
    rgame_transform_stack_init(&s);
    rgame_transform_push_rotate(&s, 3.14159f, 0.0f, 0.0f);
    float x, y;
    map(&s, 1.0f, 0.0f, &x, &y);
    ck_assert_float_gt(x, 0.99f);
}
END_TEST

START_TEST(a_full_turn_is_a_no_op) {
    rgame_transform_stack s;
    rgame_transform_stack_init(&s);
    rgame_transform_push_rotate(&s, 360.0f, 10.0f, 20.0f);

    ck_point(&s, 33.0f, 44.0f, 33.0f, 44.0f);
}
END_TEST

/* --- composition --- */

START_TEST(nesting_applies_the_inner_transform_first) {
    /*
     * `translated(100, 0) { rotated(90) { draw } }` must rotate the point about
     * the origin and *then* move the result — not rotate the already-moved
     * point about the world origin, which would fling it somewhere else.
     */
    rgame_transform_stack s;
    rgame_transform_stack_init(&s);
    rgame_transform_push_translate(&s, 100.0f, 0.0f);
    rgame_transform_push_rotate(&s, 90.0f, 0.0f, 0.0f);

    /* (1,0) rotates to (0,1), then translates to (100,1). */
    ck_point(&s, 1.0f, 0.0f, 100.0f, 1.0f);
}
END_TEST

START_TEST(the_opposite_nesting_gives_a_different_answer) {
    /* Guards the order chosen above: if composition were the other way round
     * these two would agree, and the previous test would prove nothing. */
    rgame_transform_stack s;
    rgame_transform_stack_init(&s);
    rgame_transform_push_rotate(&s, 90.0f, 0.0f, 0.0f);
    rgame_transform_push_translate(&s, 100.0f, 0.0f);

    /* (1,0) translates to (101,0), then rotates to (0,101). */
    ck_point(&s, 1.0f, 0.0f, 0.0f, 101.0f);
}
END_TEST

START_TEST(deep_nesting_still_lands_where_the_maths_says) {
    /* Ten translations compose into one; the point of keeping only the
     * composed result is that depth costs nothing per vertex. */
    rgame_transform_stack s;
    rgame_transform_stack_init(&s);
    for (int i = 0; i < 10; i++) {
        ck_assert_int_eq(rgame_transform_push_translate(&s, 1.0f, 2.0f), 1);
    }

    ck_assert_int_eq(rgame_transform_depth(&s), 10);
    ck_point(&s, 0.0f, 0.0f, 10.0f, 20.0f);
}
END_TEST

START_TEST(scale_and_rotate_compose) {
    rgame_transform_stack s;
    rgame_transform_stack_init(&s);
    rgame_transform_push_scale(&s, 2.0f, 2.0f);
    rgame_transform_push_rotate(&s, 90.0f, 0.0f, 0.0f);

    /* (1,0) -> rotate -> (0,1) -> scale -> (0,2). */
    ck_point(&s, 1.0f, 0.0f, 0.0f, 2.0f);
}
END_TEST

/* --- the stack itself --- */

START_TEST(pop_restores_the_previous_transform_exactly) {
    rgame_transform_stack s;
    rgame_transform_stack_init(&s);
    rgame_transform_push_translate(&s, 10.0f, 10.0f);

    rgame_transform_push_rotate(&s, 45.0f, 3.0f, 4.0f);
    rgame_transform_push_scale(&s, 7.0f, 9.0f);
    rgame_transform_pop(&s);
    rgame_transform_pop(&s);

    ck_assert_int_eq(rgame_transform_depth(&s), 1);
    ck_point(&s, 1.0f, 1.0f, 11.0f, 11.0f);
}
END_TEST

START_TEST(popping_back_to_the_base_restores_the_identity) {
    rgame_transform_stack s;
    rgame_transform_stack_init(&s);
    rgame_transform_push_rotate(&s, 33.0f, 5.0f, 6.0f);
    rgame_transform_pop(&s);

    ck_assert_int_eq(rgame_transform_is_identity(&s), 1);
    ck_point(&s, 8.0f, 9.0f, 8.0f, 9.0f);
}
END_TEST

START_TEST(popping_an_empty_stack_is_harmless) {
    /* A mismatched pop should not underflow into whatever precedes the array. */
    rgame_transform_stack s;
    rgame_transform_stack_init(&s);
    rgame_transform_pop(&s);
    rgame_transform_pop(&s);

    ck_assert_int_eq(rgame_transform_depth(&s), 0);
    ck_point(&s, 4.0f, 5.0f, 4.0f, 5.0f);
}
END_TEST

START_TEST(overflowing_the_stack_is_reported_and_changes_nothing) {
    rgame_transform_stack s;
    rgame_transform_stack_init(&s);

    int pushed = 0;
    while (rgame_transform_push_translate(&s, 1.0f, 0.0f)) {
        pushed++;
        ck_assert_int_lt(pushed, RGAME_TRANSFORM_STACK_DEPTH + 1);
    }

    /* The refusal is reported rather than scribbling past the end, and the
     * transform in force is still the last good one. */
    ck_assert_int_eq(rgame_transform_depth(&s), pushed);
    ck_point(&s, 0.0f, 0.0f, (float)pushed, 0.0f);

    /* A refused push must not be followed by a pop, but the stack is still
     * usable: popping once returns to one fewer translation. */
    rgame_transform_pop(&s);
    ck_point(&s, 0.0f, 0.0f, (float)(pushed - 1), 0.0f);
}
END_TEST

Suite *transform_suite(void) {
    Suite *suite = suite_create("transform");

    TCase *tc_basics = tcase_create("operations");
    tcase_add_test(tc_basics, a_fresh_stack_leaves_points_alone);
    tcase_add_test(tc_basics, translate_moves_a_point_by_the_offset);
    tcase_add_test(tc_basics, scale_multiplies_each_axis_independently);
    tcase_add_test(tc_basics, a_negative_scale_mirrors_which_is_how_flip_x_works);
    suite_add_tcase(suite, tc_basics);

    TCase *tc_rotate = tcase_create("rotation");
    tcase_add_test(tc_rotate, a_positive_angle_turns_clockwise_on_screen);
    tcase_add_test(tc_rotate, rotating_about_a_pivot_leaves_the_pivot_fixed);
    tcase_add_test(tc_rotate, rotating_about_a_pivot_swings_the_surrounding_points);
    tcase_add_test(tc_rotate, angles_are_degrees_not_radians);
    tcase_add_test(tc_rotate, a_full_turn_is_a_no_op);
    suite_add_tcase(suite, tc_rotate);

    TCase *tc_compose = tcase_create("composition");
    tcase_add_test(tc_compose, nesting_applies_the_inner_transform_first);
    tcase_add_test(tc_compose, the_opposite_nesting_gives_a_different_answer);
    tcase_add_test(tc_compose, deep_nesting_still_lands_where_the_maths_says);
    tcase_add_test(tc_compose, scale_and_rotate_compose);
    suite_add_tcase(suite, tc_compose);

    TCase *tc_stack = tcase_create("stack");
    tcase_add_test(tc_stack, pop_restores_the_previous_transform_exactly);
    tcase_add_test(tc_stack, popping_back_to_the_base_restores_the_identity);
    tcase_add_test(tc_stack, popping_an_empty_stack_is_harmless);
    tcase_add_test(tc_stack, overflowing_the_stack_is_reported_and_changes_nothing);
    suite_add_tcase(suite, tc_stack);

    return suite;
}
