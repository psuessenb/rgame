#include <check.h>
#include <stdlib.h>

#include "suites.h"

/*
 * The single entry point for the Check suite (`make test`).
 *
 * Check runs each test in its own forked process, so a segfault fails only
 * that test instead of aborting the run — worth knowing, because it is also
 * what makes a sanitizer build report a leak as an error against the specific
 * test that leaked. See .claude/skills/verify/SKILL.md.
 */

int main(void) {
    SRunner *runner = srunner_create(frame_loop_suite());
    srunner_add_suite(runner, device_slots_suite());
    srunner_add_suite(runner, input_suite());
    srunner_add_suite(runner, color_suite());
    srunner_add_suite(runner, transform_suite());
    srunner_add_suite(runner, clip_suite());
    srunner_add_suite(runner, draw_queue_suite());
    srunner_add_suite(runner, canvas_suite());
    srunner_add_suite(runner, backend_suite());
    srunner_add_suite(runner, texture_suite());
    srunner_add_suite(runner, primitives_suite());
    srunner_add_suite(runner, recording_suite());
    srunner_add_suite(runner, atlas_suite());
    srunner_add_suite(runner, glyph_cache_suite());
    srunner_add_suite(runner, font_suite());

    srunner_run_all(runner, CK_NORMAL);
    int failed = srunner_ntests_failed(runner);
    srunner_free(runner);

    return failed == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
