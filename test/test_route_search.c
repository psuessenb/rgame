#include <check.h>
#include <string.h>

#include "route_search.h"
#include "suites.h"

/*
 * The route rules themselves — optimal cost, determinism, the exact routes —
 * are pinned by spec/rgame/engine/nav_grid_spec.rb, which both the Ruby search
 * and this one have answered to. What is here is what only C can see: when the
 * labels are recomputed, what the heap allocates, and the stamps wrapping.
 */

/* A grid drawn as rows of text, '#' solid. */
static void grid_from(rgame_solid_grid *grid, const char *const rows[], int32_t height) {
    int32_t width = (int32_t)strlen(rows[0]);
    ck_assert(rgame_solid_grid_init(grid, width, height));
    for (int32_t row = 0; row < height; row++) {
        for (int32_t col = 0; col < width; col++) {
            rgame_solid_grid_set(grid, col, row, rows[row][col] == '#');
        }
    }
}

/* --- the neighbour rule --- */

START_TEST(a_diagonal_past_one_solid_orthogonal_is_not_a_neighbour) {
    static const char *const rows[] = { ".#", ".." };
    rgame_solid_grid grid;
    grid_from(&grid, rows, 2);
    int32_t cells[8];
    double steps[8];

    int count = rgame_route_neighbours(&grid, 0, cells, steps);

    ck_assert_int_eq(count, 1);
    ck_assert_int_eq(cells[0], 2);
    ck_assert_double_eq(steps[0], 1.0);
    rgame_solid_grid_free(&grid);
}

END_TEST

START_TEST(an_open_corner_reaches_its_diagonal_at_the_diagonal_cost) {
    static const char *const rows[] = { "..", ".." };
    rgame_solid_grid grid;
    grid_from(&grid, rows, 2);
    int32_t cells[8];
    double steps[8];

    int count = rgame_route_neighbours(&grid, 0, cells, steps);

    ck_assert_int_eq(count, 3);
    ck_assert_int_eq(cells[2], 3);
    ck_assert_double_eq_tol(steps[2], 1.41421356, 1e-8);
    rgame_solid_grid_free(&grid);
}

END_TEST

/* --- regions follow the grid --- */

START_TEST(walling_a_region_in_two_splits_its_label_without_a_rebuild) {
    static const char *const rows[] = { ".....", ".....", "....." };
    rgame_solid_grid grid;
    grid_from(&grid, rows, 3);
    rgame_route_search search;
    ck_assert(rgame_route_search_init(&search, &grid));
    ck_assert_int_eq(rgame_route_region(&search, 0, 0), rgame_route_region(&search, 4, 2));

    for (int32_t row = 0; row < 3; row++) {
        rgame_solid_grid_set(&grid, 2, row, true);
    }

    ck_assert_int_ne(rgame_route_region(&search, 0, 0), rgame_route_region(&search, 4, 2));
    ck_assert_int_eq(rgame_route_region(&search, 2, 1), -1);
    ck_assert_int_eq(rgame_route_find(&search, 0, 0, 4, 2), RGAME_ROUTE_NONE);

    rgame_route_search_free(&search);
    rgame_solid_grid_free(&grid);
}

END_TEST

START_TEST(opening_the_wall_again_joins_the_labels_and_routes_through) {
    static const char *const rows[] = { "..#..", "..#..", "..#.." };
    rgame_solid_grid grid;
    grid_from(&grid, rows, 3);
    rgame_route_search search;
    ck_assert(rgame_route_search_init(&search, &grid));
    ck_assert_int_ne(rgame_route_region(&search, 0, 0), rgame_route_region(&search, 4, 2));

    rgame_solid_grid_set(&grid, 2, 1, false);

    ck_assert_int_eq(rgame_route_region(&search, 0, 0), rgame_route_region(&search, 4, 2));
    ck_assert_int_eq(rgame_route_find(&search, 0, 1, 4, 1), RGAME_ROUTE_FOUND);
    ck_assert_int_eq(search.route_length, 5);
    ck_assert_int_eq(search.route[2], 1 * 5 + 2);

    rgame_route_search_free(&search);
    rgame_solid_grid_free(&grid);
}

END_TEST

START_TEST(the_labels_are_not_recomputed_while_the_grid_stands_still) {
    static const char *const rows[] = { "..#..", "..#.." };
    rgame_solid_grid grid;
    grid_from(&grid, rows, 2);
    rgame_route_search search;
    ck_assert(rgame_route_search_init(&search, &grid));
    int32_t left = rgame_route_region(&search, 0, 0);

    /* Scribble over the labels: a relabel would put them back, a lookup does not. */
    search.regions[0] = 99;
    rgame_solid_grid_set(&grid, 0, 1, false);

    ck_assert_int_eq(rgame_route_region(&search, 0, 0), 99);

    rgame_solid_grid_set(&grid, 0, 1, true);
    ck_assert_int_eq(rgame_route_region(&search, 0, 0), left);

    rgame_route_search_free(&search);
    rgame_solid_grid_free(&grid);
}

END_TEST

/* --- what a search keeps between queries --- */

/* Open ground with a wall across it, open only at the far end, and the goal
 * just past the gap: the search floods nearly the whole grid on a wide frontier,
 * and still has cells queued when it arrives. */
static void walled(rgame_solid_grid *grid, int32_t size) {
    ck_assert(rgame_solid_grid_init(grid, size, size));
    for (int32_t col = 1; col < size; col++) {
        rgame_solid_grid_set(grid, col, size - 2, true);
    }
}

START_TEST(a_repeated_worst_case_query_does_not_grow_the_heap) {
    rgame_solid_grid grid;
    walled(&grid, 64);
    rgame_route_search search;
    ck_assert(rgame_route_search_init(&search, &grid));

    ck_assert_int_eq(rgame_route_find(&search, 63, 0, 1, 63), RGAME_ROUTE_FOUND);
    size_t capacity = search.heap_capacity;
    const int32_t *heap = search.heap_cell;
    int32_t length = search.route_length;
    ck_assert_uint_gt(capacity, 64);

    /* Several times, since a search that left entries behind for the next one
     * would fit them in the spare capacity once or twice before it grew. */
    for (int repeat = 0; repeat < 8; repeat++) {
        ck_assert_int_eq(rgame_route_find(&search, 63, 0, 1, 63), RGAME_ROUTE_FOUND);
        ck_assert_uint_eq(search.heap_capacity, capacity);
        ck_assert_ptr_eq(search.heap_cell, heap);
        ck_assert_int_eq(search.route_length, length);
    }

    rgame_route_search_free(&search);
    rgame_solid_grid_free(&grid);
}

END_TEST

START_TEST(the_generation_stamp_wrapping_clears_what_the_last_search_left) {
    static const char *const rows[] = { "....." };
    rgame_solid_grid grid;
    grid_from(&grid, rows, 1);
    rgame_route_search search;
    ck_assert(rgame_route_search_init(&search, &grid));
    ck_assert_int_eq(rgame_route_find(&search, 0, 0, 4, 0), RGAME_ROUTE_FOUND);
    ck_assert_uint_eq(search.generation, 1);

    /* The next search wraps back onto stamp 1 — the one every cell above is
     * closed with — so only a clear lets it start at all. */
    search.generation = UINT32_MAX;
    ck_assert_int_eq(rgame_route_find(&search, 0, 0, 4, 0), RGAME_ROUTE_FOUND);

    ck_assert_uint_eq(search.generation, 1);
    ck_assert_int_eq(search.route_length, 5);
    for (int32_t i = 0; i < 5; i++) {
        ck_assert_int_eq(search.route[i], i);
    }
    rgame_route_search_free(&search);
    rgame_solid_grid_free(&grid);
}

END_TEST

START_TEST(an_empty_grid_finds_nothing_and_labels_nothing) {
    rgame_solid_grid grid;
    ck_assert(rgame_solid_grid_init(&grid, 0, 0));
    rgame_route_search search;
    ck_assert(rgame_route_search_init(&search, &grid));

    ck_assert_int_eq(rgame_route_region(&search, 0, 0), -1);
    ck_assert_int_eq(rgame_route_find(&search, 0, 0, 0, 0), RGAME_ROUTE_NONE);

    rgame_route_search_free(&search);
    rgame_solid_grid_free(&grid);
}

END_TEST

Suite *route_search_suite(void) {
    Suite *suite = suite_create("route_search");

    TCase *neighbours = tcase_create("the neighbour rule");
    tcase_add_test(neighbours, a_diagonal_past_one_solid_orthogonal_is_not_a_neighbour);
    tcase_add_test(neighbours, an_open_corner_reaches_its_diagonal_at_the_diagonal_cost);
    suite_add_tcase(suite, neighbours);

    TCase *regions = tcase_create("regions follow the grid");
    tcase_add_test(regions, walling_a_region_in_two_splits_its_label_without_a_rebuild);
    tcase_add_test(regions, opening_the_wall_again_joins_the_labels_and_routes_through);
    tcase_add_test(regions, the_labels_are_not_recomputed_while_the_grid_stands_still);
    suite_add_tcase(suite, regions);

    TCase *kept = tcase_create("what a search keeps between queries");
    tcase_add_test(kept, a_repeated_worst_case_query_does_not_grow_the_heap);
    tcase_add_test(kept, the_generation_stamp_wrapping_clears_what_the_last_search_left);
    tcase_add_test(kept, an_empty_grid_finds_nothing_and_labels_nothing);
    suite_add_tcase(suite, kept);

    return suite;
}
