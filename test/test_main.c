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
 *
 * ---------------------------------------------------------------------------
 * Why macOS runs the audio suite in a second runner
 * ---------------------------------------------------------------------------
 *
 * On macOS, opening a CoreAudio device inside a forked child can be killed by
 * the OS outright. macOS reports it in the crash log as *"crashed on child
 * side of fork pre-exec"*: `ma_engine_init` reaches
 * `ma_device_init__coreaudio` -> `AudioComponentInstanceNew`, which resolves an
 * audio component by **loading its bundle**, and loading a bundle in a child
 * that has forked without `exec` is one of the things Apple's frameworks refuse
 * to do rather than risk. Check's whole model is fork-per-test, so every test
 * that opens a real device is in exactly that position.
 *
 * It does not reproduce everywhere, which is what makes it a trap rather than
 * an obvious rule: whether the component's bundle is already resolved in the
 * parent (and so inherited across the fork) differs by machine and audio
 * configuration. It passes on a developer Mac with a sound card and failed all
 * 19 real-device tests on GitHub's macOS runner.
 *
 * Check's fork status is a property of an `SRunner`, not of a suite or a test
 * case, so the narrowest available fix is a *second runner*: everything else
 * keeps fork isolation, and only the suite that must talk to CoreAudio gives it
 * up. That is a real loss for that one suite — a crash there now takes the
 * process with it, as it already does everywhere on Windows (see
 * docs/plans/cross-platform-support.md, B5) — and it buys the 19 tests actually
 * running, which is the better trade.
 *
 * `srunner_set_fork_status` overrides the `CK_FORK` environment variable, so
 * `CK_FORK=yes` cannot put this suite back on the forking path on macOS. That
 * is deliberate: it is not a preference, it is what the OS permits.
 */

/* Every suite except audio, which is added by the caller below so that macOS
 * can put it in a runner of its own. */
static SRunner *create_main_runner(void) {
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
    srunner_add_suite(runner, vorbis_decoder_suite());
    return runner;
}

static int run_and_free(SRunner *runner) {
    srunner_run_all(runner, CK_NORMAL);
    int failed = srunner_ntests_failed(runner);
    srunner_free(runner);
    return failed;
}

int main(void) {
    SRunner *runner = create_main_runner();

#ifndef __APPLE__
    srunner_add_suite(runner, audio_suite());
#endif

    int failed = run_and_free(runner);

#ifdef __APPLE__
    /* See the header comment: CoreAudio cannot be opened in a forked child. */
    SRunner *audio = srunner_create(audio_suite());
    srunner_set_fork_status(audio, CK_NOFORK);
    failed += run_and_free(audio);
#endif

    return failed == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
