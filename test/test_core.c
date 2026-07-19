#include <check.h>
#include <stdlib.h>

#include "internal.h"

START_TEST(wrap_stays_within_range) {
    double result = rgame_wrap_angle_degrees(10.0, 20.0);
    ck_assert_double_eq_tol(result, 30.0, 1e-9);
}
END_TEST

START_TEST(wrap_crosses_360) {
    double result = rgame_wrap_angle_degrees(350.0, 20.0);
    ck_assert_double_eq_tol(result, 10.0, 1e-9);
}
END_TEST

START_TEST(wrap_handles_negative_delta) {
    double result = rgame_wrap_angle_degrees(10.0, -20.0);
    ck_assert_double_eq_tol(result, 350.0, 1e-9);
}
END_TEST

static Suite *core_suite(void) {
    Suite *suite = suite_create("core");

    TCase *tcase = tcase_create("wrap_angle_degrees");
    tcase_add_test(tcase, wrap_stays_within_range);
    tcase_add_test(tcase, wrap_crosses_360);
    tcase_add_test(tcase, wrap_handles_negative_delta);
    suite_add_tcase(suite, tcase);

    return suite;
}

int main(void) {
    Suite *suite = core_suite();
    SRunner *runner = srunner_create(suite);

    srunner_run_all(runner, CK_NORMAL);
    int failed = srunner_ntests_failed(runner);
    srunner_free(runner);

    return failed == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
