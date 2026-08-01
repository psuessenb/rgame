#ifndef RGAME_TEST_SUITES_H
#define RGAME_TEST_SUITES_H

#include <check.h>

/*
 * Every test file builds one Check Suite and declares it here; test_main.c
 * runs them all in a single binary. Adding a layer-1 module therefore means
 * adding one file, one line here, and one line in test_main.c — rather than
 * another copy of main() and another target in the Makefile.
 */

Suite *frame_loop_suite(void);
Suite *device_slots_suite(void);
Suite *input_suite(void);

#endif /* RGAME_TEST_SUITES_H */
