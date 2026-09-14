#include <check.h>
#include <math.h>
#include <string.h>

#include "solid_grid.h"
#include "suites.h"
#include "tile_sweep.h"

/* A grid drawn as rows of text, '#' solid and anything else open. */
static void draw(rgame_solid_grid *grid, int32_t rows, const char *const lines[]) {
    int32_t width = (int32_t)strlen(lines[0]);
    ck_assert(rgame_solid_grid_init(grid, width, rows));
    for (int32_t row = 0; row < rows; row++) {
        for (int32_t col = 0; col < width; col++) {
            rgame_solid_grid_set(grid, col, row, lines[row][col] == '#');
        }
    }
}

/* 16px tiles over a 20x20 grid whose column 5 (x 80..96) and row 5 (y 80..96) are solid. */
static void cross(rgame_solid_grid *grid, rgame_tile_sweep *sweep) {
    ck_assert(rgame_solid_grid_init(grid, 20, 20));
    for (int32_t i = 0; i < 20; i++) {
        rgame_solid_grid_set(grid, 5, i, true);
        rgame_solid_grid_set(grid, i, 5, true);
    }
    *sweep = (rgame_tile_sweep){ .grid = grid, .tile_width = 16.0, .tile_height = 16.0 };
}

/* --- resolving a step --- */

START_TEST(a_step_snaps_flush_against_a_solid_tile_on_each_side) {
    rgame_solid_grid grid;
    rgame_tile_sweep sweep;
    cross(&grid, &sweep);

    /* Right edge 74 + 10 enters the column at x 80: the box rests with its right edge on 80. */
    ck_assert_double_eq(rgame_tile_sweep_resolve_x(&sweep, 58, 0, 16, 16, 10), 64);
    /* Left edge 100 - 8 enters the column's right half: the box rests on 96. */
    ck_assert_double_eq(rgame_tile_sweep_resolve_x(&sweep, 100, 0, 16, 16, -8), 96);
    ck_assert_double_eq(rgame_tile_sweep_resolve_y(&sweep, 0, 60, 16, 16, 10), 64);
    ck_assert_double_eq(rgame_tile_sweep_resolve_y(&sweep, 0, 100, 16, 16, -8), 96);
    rgame_solid_grid_free(&grid);
}

END_TEST

START_TEST(a_step_through_open_ground_lands_where_it_was_heading) {
    rgame_solid_grid grid;
    rgame_tile_sweep sweep;
    cross(&grid, &sweep);

    ck_assert_double_eq(rgame_tile_sweep_resolve_x(&sweep, 16.5, 20.25, 12, 6, 1.5), 18.0);
    ck_assert_double_eq(rgame_tile_sweep_resolve_y(&sweep, 16.5, 20.25, 12, 6, -1.5), 18.75);
    /* Flush against the column already, moving away from it. */
    ck_assert_double_eq(rgame_tile_sweep_resolve_x(&sweep, 64, 0, 16, 16, -3), 61);
    rgame_solid_grid_free(&grid);
}

END_TEST

START_TEST(a_zero_step_returns_the_box_where_it_is) {
    rgame_solid_grid grid;
    rgame_tile_sweep sweep;
    cross(&grid, &sweep);

    /* Even from inside a solid tile: no movement, nothing to resolve. */
    ck_assert_double_eq(rgame_tile_sweep_resolve_x(&sweep, 84, 84, 4, 4, 0), 84);
    ck_assert_double_eq(rgame_tile_sweep_resolve_y(&sweep, 84, 84, 4, 4, 0), 84);
    rgame_solid_grid_free(&grid);
}

END_TEST

START_TEST(outside_the_grid_is_open) {
    rgame_solid_grid grid;
    rgame_tile_sweep sweep;
    cross(&grid, &sweep);

    /* Beyond the right edge, and above the top, on the solid row's and column's lines. */
    ck_assert_double_eq(rgame_tile_sweep_resolve_x(&sweep, 400, 84, 12, 6, 30), 430);
    ck_assert_double_eq(rgame_tile_sweep_resolve_y(&sweep, 84, -80, 6, 12, 30), -50);
    ck_assert_double_eq(rgame_tile_sweep_resolve_x(&sweep, -40, 84, 12, 6, -30), -70);
    rgame_solid_grid_free(&grid);
}

END_TEST

START_TEST(coordinates_far_outside_the_grid_are_open_and_well_defined) {
    rgame_solid_grid grid;
    rgame_tile_sweep sweep;
    cross(&grid, &sweep);

    ck_assert_double_eq(rgame_tile_sweep_resolve_x(&sweep, 1e12, 1e12, 12, 6, 5), 1e12 + 5);
    ck_assert_double_eq(rgame_tile_sweep_resolve_x(&sweep, -1e12, -1e12, 12, 6, -5), -1e12 - 5);
    ck_assert_double_eq(rgame_tile_sweep_resolve_y(&sweep, 1e300, -1e300, 12, 6, 5), -1e300);
    ck_assert(isinf(rgame_tile_sweep_resolve_x(&sweep, INFINITY, 0, 12, 6, 5)));
    ck_assert(isnan(rgame_tile_sweep_resolve_x(&sweep, NAN, 0, 12, 6, 5)));
    ck_assert(isnan(rgame_tile_sweep_resolve_y(&sweep, 0, NAN, 12, 6, 5)));
    /* A NaN on the other axis spans no tiles at all, so nothing can stop the step. */
    ck_assert_double_eq(rgame_tile_sweep_resolve_x(&sweep, 0, NAN, 12, 6, 5), 5);
    ck_assert_double_eq(rgame_tile_sweep_resolve_y(&sweep, NAN, 0, 12, 6, 5), 5);
    rgame_solid_grid_free(&grid);
}

END_TEST

START_TEST(a_box_taller_than_the_grid_is_clamped_to_the_rows_that_exist) {
    rgame_solid_grid grid;
    rgame_tile_sweep sweep;
    cross(&grid, &sweep);

    /* Spans every row there is and billions that are not; the column still stops it. */
    ck_assert_double_eq(rgame_tile_sweep_resolve_x(&sweep, 58, -5e11, 16, 1e12, 10), 64);
    rgame_solid_grid_free(&grid);
}

END_TEST

START_TEST(a_box_resting_flush_on_a_tile_edge_does_not_overlap_that_tile) {
    /* The box's bottom edge lies exactly on the line between rows 0 and 1, and the only
     * solid tile is in row 1: moving right past it along row 0 is free. */
    rgame_solid_grid grid;
    draw(&grid, 2, (const char *const[]){ "....", ".#.." });
    rgame_tile_sweep sweep = { .grid = &grid, .tile_width = 16.0, .tile_height = 16.0 };

    ck_assert_double_eq(rgame_tile_sweep_resolve_x(&sweep, 0, 0, 12, 16, 10), 10);
    ck_assert_double_eq(rgame_tile_sweep_resolve_y(&sweep, 0, 0, 16, 12, 10), 10);
    rgame_solid_grid_free(&grid);
}

END_TEST

/* --- travelling --- */

START_TEST(a_box_travels_open_ground_and_not_through_a_wall) {
    rgame_solid_grid grid;
    rgame_tile_sweep sweep;
    cross(&grid, &sweep);

    ck_assert(rgame_tile_sweep_travel(&sweep, 2, 2, 12, 6, 60, 50));
    ck_assert(!rgame_tile_sweep_travel(&sweep, 2, 2, 12, 6, 200, 0));
    ck_assert(!rgame_tile_sweep_travel(&sweep, 2, 2, 12, 6, 0, 200));
    rgame_solid_grid_free(&grid);
}

END_TEST

START_TEST(a_box_is_refused_a_corner_a_point_clears) {
    /* From the centre of (0, 0) to the centre of (5, 2), the line passes 1.6 px above the
     * tree's top-left corner. */
    rgame_solid_grid grid;
    draw(&grid, 4, (const char *const[]){ "......", "......", "...#..", "......" });
    rgame_tile_sweep sweep = { .grid = &grid, .tile_width = 16.0, .tile_height = 16.0 };

    ck_assert(rgame_tile_sweep_travel(&sweep, 8, 8, 0, 0, 80, 32));
    ck_assert(!rgame_tile_sweep_travel(&sweep, 8 - 6, 8 - 3, 12, 6, 80, 32));
    rgame_solid_grid_free(&grid);
}

END_TEST

START_TEST(a_window_is_resolved_both_ways_round) {
    /* A 4x4 box moving (8, 8) from (10, 10): X first slides past the solid tile below it and
     * lands in the open; Y first drops straight into that tile. */
    rgame_solid_grid grid;
    draw(&grid, 2, (const char *const[]){ "..", "#." });
    rgame_tile_sweep sweep = { .grid = &grid, .tile_width = 16.0, .tile_height = 16.0 };

    double x = rgame_tile_sweep_resolve_x(&sweep, 10, 10, 4, 4, 8);
    ck_assert_double_eq(rgame_tile_sweep_resolve_y(&sweep, x, 10, 4, 4, 8), 18);
    ck_assert(!rgame_tile_sweep_travel(&sweep, 10, 10, 4, 4, 8, 8));
    rgame_solid_grid_free(&grid);
}

END_TEST

START_TEST(a_travel_shorter_than_a_window_and_a_travel_of_nothing) {
    rgame_solid_grid grid;
    rgame_tile_sweep sweep;
    cross(&grid, &sweep);

    ck_assert_double_eq(rgame_tile_sweep_travel_windows(&sweep, 2, -1), 1);
    ck_assert(rgame_tile_sweep_travel(&sweep, 62, 20, 16, 6, 2, 0));
    ck_assert(!rgame_tile_sweep_travel(&sweep, 62, 20, 16, 6, 3, 0));
    /* Nothing moves, so nothing falls short — even from inside a solid tile. */
    ck_assert(rgame_tile_sweep_travel(&sweep, 84, 84, 4, 4, 0, 0));
    rgame_solid_grid_free(&grid);
}

END_TEST

START_TEST(the_window_count_follows_the_longer_axis_at_a_quarter_tile) {
    rgame_solid_grid grid;
    rgame_solid_grid_init(&grid, 1, 1);
    rgame_tile_sweep sweep = { .grid = &grid, .tile_width = 16.0, .tile_height = 8.0 };

    ck_assert_double_eq(rgame_tile_sweep_travel_windows(&sweep, 16, 0), 4);
    ck_assert_double_eq(rgame_tile_sweep_travel_windows(&sweep, -17, 0), 5);
    ck_assert_double_eq(rgame_tile_sweep_travel_windows(&sweep, 16, 16), 8);
    ck_assert_double_eq(rgame_tile_sweep_travel_windows(&sweep, 0, 0), 1);
    rgame_solid_grid_free(&grid);
}

END_TEST

START_TEST(a_travel_too_long_to_sweep_is_refused_without_sweeping) {
    rgame_solid_grid grid;
    rgame_tile_sweep sweep;
    cross(&grid, &sweep);

    ck_assert(!rgame_tile_sweep_travel(&sweep, 400, 400, 12, 6, 1e20, 0));
    ck_assert(!rgame_tile_sweep_travel(&sweep, 400, 400, 12, 6, NAN, 0));
    rgame_solid_grid_free(&grid);
}

END_TEST

Suite *tile_sweep_suite(void) {
    Suite *suite = suite_create("tile_sweep");

    TCase *resolving = tcase_create("resolving a step");
    tcase_add_test(resolving, a_step_snaps_flush_against_a_solid_tile_on_each_side);
    tcase_add_test(resolving, a_step_through_open_ground_lands_where_it_was_heading);
    tcase_add_test(resolving, a_zero_step_returns_the_box_where_it_is);
    tcase_add_test(resolving, outside_the_grid_is_open);
    tcase_add_test(resolving, coordinates_far_outside_the_grid_are_open_and_well_defined);
    tcase_add_test(resolving, a_box_taller_than_the_grid_is_clamped_to_the_rows_that_exist);
    tcase_add_test(resolving, a_box_resting_flush_on_a_tile_edge_does_not_overlap_that_tile);
    suite_add_tcase(suite, resolving);

    TCase *travelling = tcase_create("travelling");
    tcase_add_test(travelling, a_box_travels_open_ground_and_not_through_a_wall);
    tcase_add_test(travelling, a_box_is_refused_a_corner_a_point_clears);
    tcase_add_test(travelling, a_window_is_resolved_both_ways_round);
    tcase_add_test(travelling, a_travel_shorter_than_a_window_and_a_travel_of_nothing);
    tcase_add_test(travelling, the_window_count_follows_the_longer_axis_at_a_quarter_tile);
    tcase_add_test(travelling, a_travel_too_long_to_sweep_is_refused_without_sweeping);
    suite_add_tcase(suite, travelling);

    return suite;
}
