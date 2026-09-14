#include <check.h>

#include "solid_grid.h"
#include "suites.h"

/* --- a new grid --- */

START_TEST(a_new_grid_is_open_everywhere_at_revision_zero) {
    rgame_solid_grid grid;
    ck_assert(rgame_solid_grid_init(&grid, 4, 3));

    for (int32_t row = 0; row < 3; row++) {
        for (int32_t col = 0; col < 4; col++) {
            ck_assert(!rgame_solid_grid_solid(&grid, col, row));
        }
    }
    ck_assert_uint_eq(grid.revision, 0);
    rgame_solid_grid_free(&grid);
}

END_TEST

START_TEST(an_empty_grid_is_valid_and_has_no_inside) {
    rgame_solid_grid grid;
    ck_assert(rgame_solid_grid_init(&grid, 0, 5));

    ck_assert(!rgame_solid_grid_inside(&grid, 0, 0));
    ck_assert(!rgame_solid_grid_set(&grid, 0, 0, true));
    rgame_solid_grid_free(&grid);
}

END_TEST

START_TEST(a_size_that_cannot_be_indexed_is_refused) {
    rgame_solid_grid grid;

    ck_assert(!rgame_solid_grid_init(&grid, -1, 4));
    ck_assert(!rgame_solid_grid_init(&grid, 4, -1));
    ck_assert(!rgame_solid_grid_size_ok(65536, 65536));
    /* The largest cell count an int32_t index reaches, and one past it. */
    ck_assert(rgame_solid_grid_size_ok(INT32_MAX, 1));
    ck_assert(!rgame_solid_grid_size_ok((int64_t)INT32_MAX + 1, 1));
    ck_assert(rgame_solid_grid_size_ok(46340, 46340));
    ck_assert(!rgame_solid_grid_size_ok(46341, 46341));
}

END_TEST

/* --- writing cells --- */

START_TEST(a_cell_set_solid_reads_back_and_its_neighbours_do_not) {
    rgame_solid_grid grid;
    ck_assert(rgame_solid_grid_init(&grid, 4, 3));

    ck_assert(rgame_solid_grid_set(&grid, 2, 1, true));

    ck_assert(rgame_solid_grid_solid(&grid, 2, 1));
    ck_assert(!rgame_solid_grid_solid(&grid, 1, 1));
    ck_assert(!rgame_solid_grid_solid(&grid, 2, 0));
    ck_assert(!rgame_solid_grid_solid(&grid, 3, 1));
    rgame_solid_grid_free(&grid);
}

END_TEST

START_TEST(outside_the_grid_is_open_and_cannot_be_written) {
    rgame_solid_grid grid;
    ck_assert(rgame_solid_grid_init(&grid, 4, 3));

    ck_assert(!rgame_solid_grid_solid(&grid, -1, 0));
    ck_assert(!rgame_solid_grid_solid(&grid, 4, 0));
    ck_assert(!rgame_solid_grid_solid(&grid, 0, 3));
    ck_assert(!rgame_solid_grid_set(&grid, 4, 0, true));
    ck_assert(!rgame_solid_grid_set(&grid, 0, -1, true));
    ck_assert_uint_eq(grid.revision, 0);
    rgame_solid_grid_free(&grid);
}

END_TEST

START_TEST(the_revision_moves_on_a_change_and_only_then) {
    rgame_solid_grid grid;
    ck_assert(rgame_solid_grid_init(&grid, 4, 3));

    rgame_solid_grid_set(&grid, 1, 1, false);
    ck_assert_uint_eq(grid.revision, 0);

    rgame_solid_grid_set(&grid, 1, 1, true);
    ck_assert_uint_eq(grid.revision, 1);

    rgame_solid_grid_set(&grid, 1, 1, true);
    ck_assert_uint_eq(grid.revision, 1);

    rgame_solid_grid_set(&grid, 1, 1, false);
    ck_assert_uint_eq(grid.revision, 2);
    rgame_solid_grid_free(&grid);
}

END_TEST

Suite *solid_grid_suite(void) {
    Suite *suite = suite_create("solid_grid");

    TCase *created = tcase_create("a new grid");
    tcase_add_test(created, a_new_grid_is_open_everywhere_at_revision_zero);
    tcase_add_test(created, an_empty_grid_is_valid_and_has_no_inside);
    tcase_add_test(created, a_size_that_cannot_be_indexed_is_refused);
    suite_add_tcase(suite, created);

    TCase *written = tcase_create("writing cells");
    tcase_add_test(written, a_cell_set_solid_reads_back_and_its_neighbours_do_not);
    tcase_add_test(written, outside_the_grid_is_open_and_cannot_be_written);
    tcase_add_test(written, the_revision_moves_on_a_change_and_only_then);
    suite_add_tcase(suite, written);

    return suite;
}
