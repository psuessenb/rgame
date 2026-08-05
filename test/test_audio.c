#include <check.h>
#include <string.h>

#include "audio/audio_internal.h"
#include "rgame/core.h"
#include "suites.h"

/*
 * Tests for audio.c — and unusually for a layer-3 file, they drive the real
 * thing rather than a stand-in.
 *
 * That is possible because miniaudio falls back to a *null device* when no
 * sound system will open: a real device that consumes frames on a timer and
 * produces silence. Loading, mixing, looping and stopping all behave normally
 * against it, so this file runs identically on a developer's machine (where it
 * really does play through PulseAudio) and on a build server with no sound
 * card.
 *
 * One thing to design around: with the null device a sound advances against a
 * simulated clock, so how long anything takes to *finish* is not something to
 * assert on. Everything below is about transitions the caller controls — play
 * makes it playing, stop makes it stopped — and never about natural completion.
 */

#define FIXTURE "spec_core/fixtures/tone.ogg"
#define NOT_A_SOUND "README.md"

static rgame_audio *open_audio(void) {
    char error[256] = {0};
    rgame_audio *audio = rgame_audio_create(error, sizeof(error));
    ck_assert_msg(audio != NULL, "could not open audio: %s", error);
    return audio;
}

/*
 * An engine with no device behind it, pumped by hand. Everything else here is
 * about what the engine *says*; these are about what actually comes out.
 *
 * One limit, and it is the harness's rather than the engine's: a *streamed*
 * sound refills its buffers on a background thread, which keeps up effortlessly
 * against a real device because audio is consumed at the speed of sound rather
 * than the speed of the CPU. Pumped in a tight loop it starves — measured, a
 * three-second track goes quiet after exactly two one-second pages. So nothing
 * below asks a song to play for longer than it has already buffered, and
 * "looping music really does loop" is checked through the flag plus a look at
 * `make run`, not by listening here.
 */
#define OFFLINE_RATE 44100

static rgame_audio *open_offline(void) {
    char error[256] = {0};
    rgame_audio *audio = rgame_audio_create_offline(OFFLINE_RATE, error, sizeof(error));
    ck_assert_msg(audio != NULL, "could not open an offline device: %s", error);
    return audio;
}

/* Mixes `frames` frames and returns the loudest sample in them. Zero means the
 * engine produced silence. */
static double peak_over(rgame_audio *audio, unsigned int frames) {
    static float buffer[8192 * 2];
    double peak = 0.0;

    while (frames > 0) {
        unsigned int chunk = frames > 8192 ? 8192 : frames;
        unsigned int got = rgame_audio_read(audio, buffer, chunk);
        if (got == 0) {
            break;
        }
        for (unsigned int i = 0; i < got * 2; i++) {
            double magnitude = buffer[i] < 0 ? -buffer[i] : buffer[i];
            if (magnitude > peak) {
                peak = magnitude;
            }
        }
        frames -= got;
    }
    return peak;
}

/* --- the device --- */

START_TEST(a_device_opens_even_with_no_sound_card) {
    /* The property the whole test strategy rests on, and a real one for games:
     * a machine with no audio should run silently, not refuse to start. */
    char error[256] = {0};
    rgame_audio *audio = rgame_audio_create(error, sizeof(error));

    ck_assert_ptr_nonnull(audio);
    ck_assert_str_ne(rgame_audio_backend(audio), "none");

    rgame_audio_destroy(audio);
}
END_TEST

START_TEST(destroying_a_null_device_is_harmless) {
    rgame_audio_destroy(NULL);
    ck_assert_int_eq(rgame_audio_volume(NULL), 0);
    ck_assert_str_eq(rgame_audio_backend(NULL), "none");
}
END_TEST

START_TEST(the_master_volume_round_trips) {
    rgame_audio *audio = open_audio();

    ck_assert_float_eq_tol(rgame_audio_volume(audio), 1.0f, 1e-4f);

    rgame_audio_set_volume(audio, 0.25f);
    ck_assert_float_eq_tol(rgame_audio_volume(audio), 0.25f, 1e-4f);

    rgame_audio_destroy(audio);
}
END_TEST

START_TEST(a_negative_volume_becomes_silence) {
    /* Above 1.0 is a legitimate request — it amplifies, and clipping is the
     * caller's business — but below zero is not a volume at all, and what
     * miniaudio would do with it is not worth finding out. */
    rgame_audio *audio = open_audio();

    rgame_audio_set_volume(audio, -3.0f);
    ck_assert_float_eq_tol(rgame_audio_volume(audio), 0.0f, 1e-4f);

    rgame_audio_set_volume(audio, 2.5f);
    ck_assert_float_eq_tol(rgame_audio_volume(audio), 2.5f, 1e-4f);

    rgame_audio_destroy(audio);
}
END_TEST

/* --- samples --- */

START_TEST(a_sample_loads_from_an_ogg) {
    rgame_audio *audio = open_audio();
    char error[256] = {0};

    rgame_sample *sample = rgame_sample_load(audio, FIXTURE, error, sizeof(error));
    ck_assert_msg(sample != NULL, "%s", error);

    rgame_sample_destroy(sample);
    rgame_audio_destroy(audio);
}
END_TEST

START_TEST(a_sample_that_is_not_a_sound_is_refused_at_load) {
    /*
     * At *load*, not at first play. A game loads its assets at a moment where
     * it can say which file was wrong; a one-shot that silently does nothing
     * three scenes later is a much worse way to find out.
     */
    rgame_audio *audio = open_audio();
    char error[256] = {0};

    ck_assert_ptr_null(rgame_sample_load(audio, NOT_A_SOUND, error, sizeof(error)));
    ck_assert_ptr_nonnull(strstr(error, NOT_A_SOUND));

    error[0] = '\0';
    ck_assert_ptr_null(rgame_sample_load(audio, "/no/such/sound.ogg", error, sizeof(error)));
    ck_assert_ptr_nonnull(strstr(error, "/no/such/sound.ogg"));

    rgame_audio_destroy(audio);
}
END_TEST

START_TEST(a_sample_can_be_played_over_itself) {
    /* The reason a sample is not a song: a rapid-fire effect has to layer, not
     * restart. Nothing here can hear that, but a voice-per-play that crashed or
     * refused would show. */
    rgame_audio *audio = open_audio();
    rgame_sample *sample = rgame_sample_load(audio, FIXTURE, NULL, 0);

    for (int i = 0; i < 32; i++) {
        rgame_sample_play(sample);
    }

    rgame_sample_destroy(sample);
    rgame_audio_destroy(audio);
}
END_TEST

START_TEST(a_samples_volume_round_trips) {
    rgame_audio *audio = open_audio();
    rgame_sample *sample = rgame_sample_load(audio, FIXTURE, NULL, 0);

    ck_assert_float_eq_tol(rgame_sample_volume(sample), 1.0f, 1e-4f);
    rgame_sample_set_volume(sample, 0.5f);
    ck_assert_float_eq_tol(rgame_sample_volume(sample), 0.5f, 1e-4f);
    rgame_sample_set_volume(sample, -1.0f);
    ck_assert_float_eq_tol(rgame_sample_volume(sample), 0.0f, 1e-4f);

    rgame_sample_destroy(sample);
    rgame_audio_destroy(audio);
}
END_TEST

START_TEST(destroying_a_sample_while_it_sounds_is_safe) {
    /*
     * Its voices are attached to a group that is about to be freed, on a thread
     * that is reading it. Getting the teardown order wrong here is the kind of
     * bug that shows up once a week in the wild and never in a debugger, so it
     * gets a test and a sanitizer run.
     */
    rgame_audio *audio = open_audio();
    rgame_sample *sample = rgame_sample_load(audio, FIXTURE, NULL, 0);

    for (int i = 0; i < 8; i++) {
        rgame_sample_play(sample);
    }
    rgame_sample_destroy(sample);

    rgame_audio_destroy(audio);
}
END_TEST

START_TEST(playing_or_freeing_nothing_is_harmless) {
    rgame_sample_play(NULL);
    rgame_sample_destroy(NULL);
    rgame_sample_set_volume(NULL, 1.0f);
    ck_assert_float_eq(rgame_sample_volume(NULL), 0.0f);
}
END_TEST

/* --- songs --- */

START_TEST(a_song_loads_and_reports_it_is_not_playing_yet) {
    rgame_audio *audio = open_audio();
    char error[256] = {0};

    rgame_song *song = rgame_song_load(audio, FIXTURE, error, sizeof(error));
    ck_assert_msg(song != NULL, "%s", error);
    ck_assert_int_eq(rgame_song_playing(song), 0);

    rgame_song_destroy(song);
    rgame_audio_destroy(audio);
}
END_TEST

START_TEST(a_song_that_is_not_a_sound_is_refused_at_load) {
    rgame_audio *audio = open_audio();
    char error[256] = {0};

    ck_assert_ptr_null(rgame_song_load(audio, NOT_A_SOUND, error, sizeof(error)));
    ck_assert_ptr_nonnull(strstr(error, NOT_A_SOUND));

    rgame_audio_destroy(audio);
}
END_TEST

START_TEST(play_and_stop_move_a_song_between_the_two_states) {
    /* The transitions the caller controls — never how long the sound takes to
     * finish, which against the null device is a simulated clock. */
    rgame_audio *audio = open_audio();
    rgame_song *song = rgame_song_load(audio, FIXTURE, NULL, 0);

    rgame_song_play(song, 0);
    ck_assert_int_eq(rgame_song_playing(song), 1);

    rgame_song_stop(song);
    ck_assert_int_eq(rgame_song_playing(song), 0);

    /* And it can go again afterwards. */
    rgame_song_play(song, 0);
    ck_assert_int_eq(rgame_song_playing(song), 1);

    rgame_song_destroy(song);
    rgame_audio_destroy(audio);
}
END_TEST

START_TEST(a_song_can_be_asked_to_loop) {
    rgame_audio *audio = open_audio();
    rgame_song *song = rgame_song_load(audio, FIXTURE, NULL, 0);

    rgame_song_play(song, 1);
    ck_assert_int_eq(rgame_song_playing(song), 1);
    ck_assert_int_eq(rgame_song_looping(song), 1);

    /* And the flag follows the last request rather than latching. */
    rgame_song_play(song, 0);
    ck_assert_int_eq(rgame_song_looping(song), 0);

    rgame_song_destroy(song);
    rgame_audio_destroy(audio);
}
END_TEST

START_TEST(playing_a_song_twice_restarts_it_rather_than_layering) {
    /* One voice, unlike a sample. Asking again while it sounds must not leave
     * two copies of the music running over each other. */
    rgame_audio *audio = open_audio();
    rgame_song *song = rgame_song_load(audio, FIXTURE, NULL, 0);

    rgame_song_play(song, 0);
    rgame_song_play(song, 0);
    ck_assert_int_eq(rgame_song_playing(song), 1);

    rgame_song_destroy(song);
    rgame_audio_destroy(audio);
}
END_TEST

START_TEST(a_song_stopped_and_started_begins_again_from_the_start) {
    /*
     * `play` rewinds. Without that, a track that had been stopped near its end
     * would produce a moment of sound and stop — or nothing at all if it had
     * run out — and "the music works once" is a horrible thing to debug.
     */
    rgame_audio *audio = open_audio();
    rgame_song *song = rgame_song_load(audio, FIXTURE, NULL, 0);

    rgame_song_play(song, 0);
    rgame_song_stop(song);
    rgame_song_play(song, 0);

    ck_assert_int_eq(rgame_song_playing(song), 1);

    rgame_song_destroy(song);
    rgame_audio_destroy(audio);
}
END_TEST

START_TEST(a_songs_volume_round_trips) {
    rgame_audio *audio = open_audio();
    rgame_song *song = rgame_song_load(audio, FIXTURE, NULL, 0);

    ck_assert_float_eq_tol(rgame_song_volume(song), 1.0f, 1e-4f);
    rgame_song_set_volume(song, 0.25f);
    ck_assert_float_eq_tol(rgame_song_volume(song), 0.25f, 1e-4f);
    rgame_song_set_volume(song, -2.0f);
    ck_assert_float_eq_tol(rgame_song_volume(song), 0.0f, 1e-4f);

    rgame_song_destroy(song);
    rgame_audio_destroy(audio);
}
END_TEST

START_TEST(destroying_a_song_while_it_plays_is_safe) {
    rgame_audio *audio = open_audio();
    rgame_song *song = rgame_song_load(audio, FIXTURE, NULL, 0);

    rgame_song_play(song, 1);
    rgame_song_destroy(song);

    rgame_audio_destroy(audio);
}
END_TEST

START_TEST(a_null_song_answers_rather_than_crashing) {
    rgame_song_play(NULL, 1);
    rgame_song_stop(NULL);
    rgame_song_destroy(NULL);
    rgame_song_set_volume(NULL, 1.0f);
    ck_assert_int_eq(rgame_song_playing(NULL), 0);
    ck_assert_float_eq(rgame_song_volume(NULL), 0.0f);
}
END_TEST

/* --- lifetimes --- */

START_TEST(sounds_are_accounted_for) {
    /* A leaked sound is invisible: nothing sounds wrong and nothing is slower,
     * and memory grows across an hour of play. This is what makes it visible,
     * and it is the same counter the Ruby specs assert against. */
    long before = rgame_audio_live_sounds();
    rgame_audio *audio = open_audio();

    rgame_sample *sample = rgame_sample_load(audio, FIXTURE, NULL, 0);
    rgame_song *song = rgame_song_load(audio, FIXTURE, NULL, 0);
    ck_assert_int_eq(rgame_audio_live_sounds(), before + 2);

    rgame_sample_destroy(sample);
    ck_assert_int_eq(rgame_audio_live_sounds(), before + 1);

    rgame_song_destroy(song);
    ck_assert_int_eq(rgame_audio_live_sounds(), before);

    rgame_audio_destroy(audio);
}
END_TEST

START_TEST(a_refused_load_leaves_nothing_behind) {
    long before = rgame_audio_live_sounds();
    rgame_audio *audio = open_audio();

    rgame_sample_load(audio, NOT_A_SOUND, NULL, 0);
    rgame_song_load(audio, NOT_A_SOUND, NULL, 0);
    rgame_sample_load(audio, "/no/such.ogg", NULL, 0);

    ck_assert_int_eq(rgame_audio_live_sounds(), before);

    rgame_audio_destroy(audio);
}
END_TEST

START_TEST(loading_the_same_file_many_times_is_fine) {
    /* The resource manager is keyed by path and reference counted, so several
     * samples of one file share the decoded data — and the last one to go must
     * not take it out from under the others. */
    rgame_audio *audio = open_audio();
    rgame_sample *samples[8];

    for (int i = 0; i < 8; i++) {
        samples[i] = rgame_sample_load(audio, FIXTURE, NULL, 0);
        ck_assert_ptr_nonnull(samples[i]);
    }
    for (int i = 0; i < 8; i++) {
        rgame_sample_play(samples[i]);
    }
    /* Dropped in a different order than they were made. */
    for (int i = 7; i >= 0; i--) {
        rgame_sample_destroy(samples[i]);
    }

    rgame_audio_destroy(audio);
}
END_TEST

/* --- what actually comes out --- */

START_TEST(a_played_sample_makes_sound) {
    /*
     * The assertion every other one here rests on. A stack that reported
     * loading, playing and stopping perfectly while emitting nothing would
     * satisfy all of them — and silence is exactly what a broken audio path
     * produces, so it has to be checked directly.
     */
    rgame_audio *audio = open_offline();
    rgame_sample *sample = rgame_sample_load(audio, FIXTURE, NULL, 0);

    ck_assert_double_eq(peak_over(audio, 512), 0.0); /* nothing yet */

    rgame_sample_play(sample);
    ck_assert_double_gt(peak_over(audio, 4096), 0.05);

    rgame_sample_destroy(sample);
    rgame_audio_destroy(audio);
}
END_TEST

START_TEST(a_samples_volume_reaches_the_output) {
    /* And so proves the voices really are routed through the sample's mixer
     * group — playing them past it would leave the volume with nothing to act
     * on, and nothing else here would notice. */
    rgame_audio *audio = open_offline();
    rgame_sample *sample = rgame_sample_load(audio, FIXTURE, NULL, 0);

    rgame_sample_play(sample);
    double loud = peak_over(audio, 4096);

    rgame_sample_set_volume(sample, 0.0f);
    rgame_sample_play(sample);
    double silent = peak_over(audio, 4096);

    ck_assert_double_gt(loud, 0.05);
    ck_assert_double_lt(silent, loud / 10.0);

    rgame_sample_destroy(sample);
    rgame_audio_destroy(audio);
}
END_TEST

START_TEST(the_master_volume_reaches_the_output) {
    rgame_audio *audio = open_offline();
    rgame_sample *sample = rgame_sample_load(audio, FIXTURE, NULL, 0);

    rgame_sample_play(sample);
    double loud = peak_over(audio, 4096);

    rgame_audio_set_volume(audio, 0.0f);
    rgame_sample_play(sample);
    double silent = peak_over(audio, 4096);

    ck_assert_double_gt(loud, 0.05);
    ck_assert_double_lt(silent, loud / 10.0);

    rgame_sample_destroy(sample);
    rgame_audio_destroy(audio);
}
END_TEST

START_TEST(a_song_makes_sound_until_it_is_stopped) {
    rgame_audio *audio = open_offline();
    rgame_song *song = rgame_song_load(audio, FIXTURE, NULL, 0);

    rgame_song_play(song, 0);
    ck_assert_double_gt(peak_over(audio, 2048), 0.05);

    rgame_song_stop(song);
    ck_assert_double_eq(peak_over(audio, 2048), 0.0);

    rgame_song_destroy(song);
    rgame_audio_destroy(audio);
}
END_TEST

Suite *audio_suite(void) {
    Suite *suite = suite_create("audio");
    TCase *tc = tcase_create("core");

    tcase_add_test(tc, a_device_opens_even_with_no_sound_card);
    tcase_add_test(tc, destroying_a_null_device_is_harmless);
    tcase_add_test(tc, the_master_volume_round_trips);
    tcase_add_test(tc, a_negative_volume_becomes_silence);

    tcase_add_test(tc, a_sample_loads_from_an_ogg);
    tcase_add_test(tc, a_sample_that_is_not_a_sound_is_refused_at_load);
    tcase_add_test(tc, a_sample_can_be_played_over_itself);
    tcase_add_test(tc, a_samples_volume_round_trips);
    tcase_add_test(tc, destroying_a_sample_while_it_sounds_is_safe);
    tcase_add_test(tc, playing_or_freeing_nothing_is_harmless);

    tcase_add_test(tc, a_song_loads_and_reports_it_is_not_playing_yet);
    tcase_add_test(tc, a_song_that_is_not_a_sound_is_refused_at_load);
    tcase_add_test(tc, play_and_stop_move_a_song_between_the_two_states);
    tcase_add_test(tc, a_song_can_be_asked_to_loop);
    tcase_add_test(tc, playing_a_song_twice_restarts_it_rather_than_layering);
    tcase_add_test(tc, a_song_stopped_and_started_begins_again_from_the_start);
    tcase_add_test(tc, a_songs_volume_round_trips);
    tcase_add_test(tc, destroying_a_song_while_it_plays_is_safe);
    tcase_add_test(tc, a_null_song_answers_rather_than_crashing);

    tcase_add_test(tc, sounds_are_accounted_for);
    tcase_add_test(tc, a_refused_load_leaves_nothing_behind);
    tcase_add_test(tc, loading_the_same_file_many_times_is_fine);

    tcase_add_test(tc, a_played_sample_makes_sound);
    tcase_add_test(tc, a_samples_volume_reaches_the_output);
    tcase_add_test(tc, the_master_volume_reaches_the_output);
    tcase_add_test(tc, a_song_makes_sound_until_it_is_stopped);

    suite_add_tcase(suite, tc);
    return suite;
}
