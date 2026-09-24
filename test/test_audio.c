/* mkstemp is POSIX, and -std=c17 asks for strict ISO C, which hides it. Must
 * come before any include that pulls in features.h. */
#define _POSIX_C_SOURCE 200809L

#include <check.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
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

/* Where to put a scratch file: TMPDIR, TEMP or TMP, since Windows has no /tmp.
 * The same order test_vorbis_decoder.c reads them in. */
static const char *scratch_dir(void) {
    const char *candidates[] = { "TMPDIR", "TEMP", "TMP" };
    for (size_t i = 0; i < sizeof(candidates) / sizeof(candidates[0]); i++) {
        const char *dir = getenv(candidates[i]);
        if (dir && *dir) {
            return dir;
        }
    }
    return "/tmp";
}

static void put_u32(FILE *file, uint32_t value) {
    unsigned char bytes[4] = { value & 0xFF, (value >> 8) & 0xFF, (value >> 16) & 0xFF,
                               (value >> 24) & 0xFF };
    fwrite(bytes, 1, 4, file);
}

static void put_u16(FILE *file, uint16_t value) {
    unsigned char bytes[2] = { value & 0xFF, (value >> 8) & 0xFF };
    fwrite(bytes, 1, 2, file);
}

/*
 * A stereo 16-bit WAV at OFFLINE_RATE holding one constant level, written to a
 * scratch file whose path it returns. Constant, so every frame that comes out
 * is the level times the gain at that frame: a volume step reads straight off
 * the difference between two frames, with no waveform in the way.
 */
static const char *level_wav(double seconds, int16_t level) {
    static char path[512];
    int written = snprintf(path, sizeof(path), "%s/rgame_audio_levelXXXXXX", scratch_dir());
    ck_assert_int_gt(written, 0);
    ck_assert_uint_lt((size_t)written, sizeof(path));

    int fd = mkstemp(path);
    ck_assert_int_ge(fd, 0);
    FILE *file = fdopen(fd, "wb");
    ck_assert_ptr_nonnull(file);

    uint32_t frames = (uint32_t)(seconds * OFFLINE_RATE);
    uint32_t data = frames * 2 * 2;
    fwrite("RIFF", 1, 4, file);
    put_u32(file, 36 + data);
    fwrite("WAVEfmt ", 1, 8, file);
    put_u32(file, 16);
    put_u16(file, 1); /* PCM */
    put_u16(file, 2);
    put_u32(file, OFFLINE_RATE);
    put_u32(file, OFFLINE_RATE * 2 * 2);
    put_u16(file, 2 * 2);
    put_u16(file, 16);
    fwrite("data", 1, 4, file);
    put_u32(file, data);
    for (uint32_t i = 0; i < frames * 2; i++) {
        put_u16(file, (uint16_t)level);
    }
    fclose(file);
    return path;
}

/* One tick of a 60 Hz game at OFFLINE_RATE. */
#define TICK_FRAMES (OFFLINE_RATE / 60)

/*
 * Mixes `frames` frames and returns the largest change between two neighbouring
 * frames of the left channel, counting from `*last`, the frame before them,
 * which it updates. Over a constant level that is the largest volume step.
 */
static double largest_step(rgame_audio *audio, unsigned int frames, double *last) {
    static float buffer[TICK_FRAMES * 2];
    double step = 0.0;

    while (frames > 0) {
        unsigned int chunk = frames > TICK_FRAMES ? TICK_FRAMES : frames;
        unsigned int got = rgame_audio_read(audio, buffer, chunk);
        if (got == 0) {
            break;
        }
        for (unsigned int i = 0; i < got; i++) {
            double change = buffer[i * 2] - *last;
            if (change < 0) {
                change = -change;
            }
            if (change > step) {
                step = change;
            }
            *last = buffer[i * 2];
        }
        frames -= got;
    }
    return step;
}

#define LEVEL 16384 /* 0.5 of full scale */

/*
 * Plays a constant level as a song, lowers its volume from 1 to 0 in `ticks`
 * steps, one a tick, the way the engine's fade does, and returns the largest
 * step that came out.
 */
static double fade_step(int ticks) {
    rgame_audio *audio = open_offline();
    const char *path = level_wav(2.0, LEVEL);
    char error[256] = {0};
    rgame_song *song = rgame_song_load(audio, path, error, sizeof(error));
    ck_assert_msg(song != NULL, "%s", error);

    rgame_song_play(song, 0);
    double last = 0.0;
    largest_step(audio, TICK_FRAMES, &last);

    double step = 0.0;
    for (int tick = 1; tick <= ticks; tick++) {
        rgame_song_set_volume(song, 1.0f - (float)tick / (float)ticks);
        double this_tick = largest_step(audio, TICK_FRAMES, &last);
        if (this_tick > step) {
            step = this_tick;
        }
    }

    rgame_song_destroy(song);
    rgame_audio_destroy(audio);
    remove(path);
    return step;
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

/*
 * The order sounds and their device are released in is not ours to choose.
 * Ruby's collector frees unreachable objects in whatever order it sweeps them,
 * so a Song and the Audio it came from can go in one pass with the Audio first
 * — and this is that order, written down.
 *
 * Without the device's refcount it does not fail, it *hangs*: tearing down a
 * streaming voice waits for the resource manager's job thread to acknowledge
 * it, and that thread went with the engine. Check forks each test and caps it,
 * so the deadlock reads as a timeout here instead of a CI run that never ends.
 */
START_TEST(a_sound_outlives_the_device_it_came_from) {
    long before = rgame_audio_live_sounds();
    rgame_audio *audio = open_audio();
    rgame_sample *sample = rgame_sample_load(audio, FIXTURE, NULL, 0);
    rgame_song *song = rgame_song_load(audio, FIXTURE, NULL, 0);

    /* The device goes first, while both sounds are still holding it. */
    rgame_audio_destroy(audio);

    rgame_song_destroy(song);
    rgame_sample_destroy(sample);
    ck_assert_int_eq(rgame_audio_live_sounds(), before);
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

/* --- categories --- */

START_TEST(a_category_volume_multiplies_every_sound_in_it) {
    /* Each of the three volumes multiplies the others, and setting one leaves
     * the other two as they were: a settings screen that turns the effects
     * down does not change what a game set on one sample. */
    rgame_audio *audio = open_offline();
    const char *path = level_wav(0.5, LEVEL);
    rgame_sample *sample = rgame_sample_load(audio, path, NULL, 0);

    rgame_audio_set_category_volume(audio, RGAME_AUDIO_EFFECTS, 0.5f);
    rgame_sample_play(sample);
    double category = peak_over(audio, 256);

    rgame_sample_set_volume(sample, 0.5f);
    double both = peak_over(audio, 256);

    rgame_audio_set_volume(audio, 0.5f);
    double all_three = peak_over(audio, 256);

    ck_assert_double_eq_tol(category, 0.25, 1e-3);
    ck_assert_double_eq_tol(both, 0.125, 1e-3);
    ck_assert_double_eq_tol(all_three, 0.0625, 1e-3);
    ck_assert_float_eq_tol(rgame_sample_volume(sample), 0.5f, 1e-4f);
    ck_assert_float_eq_tol(rgame_audio_category_volume(audio, RGAME_AUDIO_EFFECTS), 0.5f, 1e-4f);

    rgame_sample_destroy(sample);
    rgame_audio_destroy(audio);
    remove(path);
}
END_TEST

START_TEST(a_song_plays_under_music_and_a_sample_under_effects) {
    rgame_audio *audio = open_offline();
    const char *path = level_wav(0.5, LEVEL);
    rgame_sample *sample = rgame_sample_load(audio, path, NULL, 0);
    rgame_song *song = rgame_song_load(audio, path, NULL, 0);

    rgame_audio_set_category_volume(audio, RGAME_AUDIO_MUSIC, 0.0f);
    rgame_song_play(song, 1);
    double music_off = peak_over(audio, 256);
    rgame_sample_play(sample);
    double sample_over_it = peak_over(audio, 256);

    ck_assert_double_eq(music_off, 0.0);
    ck_assert_double_eq_tol(sample_over_it, 0.5, 1e-3);

    rgame_song_destroy(song);
    rgame_sample_destroy(sample);
    rgame_audio_destroy(audio);
    remove(path);
}
END_TEST

START_TEST(a_sound_moved_to_another_category_takes_that_volume) {
    /* The last category a sound was put in is the one it plays under, and a
     * voice already sounding moves with its sample. */
    rgame_audio *audio = open_offline();
    const char *path = level_wav(0.5, LEVEL);
    rgame_sample *sample = rgame_sample_load(audio, path, NULL, 0);
    rgame_song *song = rgame_song_load(audio, path, NULL, 0);
    int voice = 5;

    rgame_audio_set_category_volume(audio, voice, 0.0f);
    rgame_sample_play(sample);
    rgame_sample_set_category(sample, voice);
    double moved = peak_over(audio, 256);
    rgame_sample_set_category(sample, RGAME_AUDIO_EFFECTS);
    double back = peak_over(audio, 256);

    rgame_song_set_category(song, voice);
    rgame_song_play(song, 1);
    double song_moved = peak_over(audio, 256);

    ck_assert_double_eq(moved, 0.0);
    ck_assert_double_eq_tol(back, 0.5, 1e-3);
    ck_assert_double_eq_tol(song_moved, 0.5, 1e-3); /* the sample still sounds */

    rgame_sample_destroy(sample);
    rgame_song_stop(song);
    ck_assert_double_eq(peak_over(audio, 4096), 0.0);

    rgame_song_destroy(song);
    rgame_audio_destroy(audio);
    remove(path);
}
END_TEST

START_TEST(a_category_volume_reads_back_and_clamps) {
    rgame_audio *audio = open_audio();

    ck_assert_float_eq_tol(rgame_audio_category_volume(audio, 9), 1.0f, 1e-4f);
    rgame_audio_set_category_volume(audio, 9, 0.25f);
    ck_assert_float_eq_tol(rgame_audio_category_volume(audio, 9), 0.25f, 1e-4f);
    rgame_audio_set_category_volume(audio, 9, -1.0f);
    ck_assert_float_eq_tol(rgame_audio_category_volume(audio, 9), 0.0f, 1e-4f);

    rgame_audio_set_category_volume(audio, RGAME_AUDIO_CATEGORIES, 0.5f);
    rgame_audio_set_category_volume(audio, -1, 0.5f);
    ck_assert_float_eq(rgame_audio_category_volume(audio, RGAME_AUDIO_CATEGORIES), 0.0f);
    ck_assert_float_eq(rgame_audio_category_volume(audio, -1), 0.0f);

    rgame_audio_destroy(audio);
}
END_TEST

START_TEST(a_category_out_of_range_leaves_a_sound_where_it_was) {
    rgame_audio *audio = open_offline();
    const char *path = level_wav(0.5, LEVEL);
    rgame_sample *sample = rgame_sample_load(audio, path, NULL, 0);

    rgame_sample_set_category(sample, RGAME_AUDIO_CATEGORIES);
    rgame_audio_set_category_volume(audio, RGAME_AUDIO_EFFECTS, 0.0f);
    rgame_sample_play(sample);

    ck_assert_double_eq(peak_over(audio, 256), 0.0);

    rgame_sample_destroy(sample);
    rgame_audio_destroy(audio);
    remove(path);
}
END_TEST

/* --- resume --- */

START_TEST(resume_carries_on_where_stop_left_the_song) {
    /* Stop then resume is a pause; stop then play starts from the top. The
     * cursor is in the file's frames, and the fixture is 11025 of them, so
     * nothing here reads far enough to reach its end. */
    rgame_audio *audio = open_offline();
    rgame_song *song = rgame_song_load(audio, FIXTURE, NULL, 0);

    rgame_song_play(song, 0);
    peak_over(audio, 4096);
    rgame_song_stop(song);
    unsigned long long stopped = rgame_song_cursor(song);
    peak_over(audio, 1024);
    unsigned long long while_stopped = rgame_song_cursor(song);

    rgame_song_resume(song);
    int playing = rgame_song_playing(song);
    peak_over(audio, 1024);
    unsigned long long resumed = rgame_song_cursor(song);

    rgame_song_stop(song);
    rgame_song_play(song, 0);
    peak_over(audio, 1024);
    unsigned long long replayed = rgame_song_cursor(song);

    ck_assert_uint_gt(stopped, 2048);
    ck_assert_uint_eq(while_stopped, stopped);
    ck_assert_int_eq(playing, 1);
    ck_assert_uint_gt(resumed, stopped);
    ck_assert_uint_lt(replayed, stopped);

    rgame_song_destroy(song);
    rgame_audio_destroy(audio);
}
END_TEST

START_TEST(resume_keeps_the_looping_the_last_play_asked_for) {
    rgame_audio *audio = open_audio();
    rgame_song *song = rgame_song_load(audio, FIXTURE, NULL, 0);

    rgame_song_play(song, 1);
    rgame_song_stop(song);
    rgame_song_resume(song);

    ck_assert_int_eq(rgame_song_playing(song), 1);
    ck_assert_int_eq(rgame_song_looping(song), 1);

    rgame_song_destroy(song);
    rgame_audio_destroy(audio);
}
END_TEST

START_TEST(a_null_device_or_sound_takes_the_new_calls) {
    rgame_audio_set_category_volume(NULL, 0, 1.0f);
    ck_assert_float_eq(rgame_audio_category_volume(NULL, 0), 0.0f);
    rgame_sample_set_category(NULL, 0);
    rgame_song_set_category(NULL, 0);
    rgame_song_resume(NULL);
    ck_assert_uint_eq(rgame_song_cursor(NULL), 0);
}
END_TEST

/* --- a volume stepped once a tick --- */

START_TEST(a_fade_stepped_once_a_tick_steps_by_one_ticks_share) {
    /* The engine fades a song by setting its volume once a tick. Nothing
     * spreads the change, so the largest step is one tick's share of the
     * level: 1/60 of it for a fade of a second, 1/30 for half a second. See
     * VOLUME_SMOOTH_FRAMES in audio.c for why nothing spreads it. */
    double level = LEVEL / 32768.0;

    ck_assert_double_le(fade_step(60), level / 60 + 1e-4);
    ck_assert_double_le(fade_step(30), level / 30 + 1e-4);
}
END_TEST

START_TEST(a_song_started_again_at_silence_starts_silent) {
    /* A fade in sets the volume to 0 and then plays. A song that last played
     * at full volume must not sound its first frames at full volume, which is
     * what spreading the change from where the volume was would do. */
    rgame_audio *audio = open_offline();
    const char *path = level_wav(1.0, LEVEL);
    rgame_song *song = rgame_song_load(audio, path, NULL, 0);

    rgame_song_play(song, 0);
    peak_over(audio, TICK_FRAMES);
    rgame_song_stop(song);
    rgame_song_set_volume(song, 0.0f);
    rgame_song_play(song, 0);

    ck_assert_double_eq(peak_over(audio, TICK_FRAMES), 0.0);

    rgame_song_destroy(song);
    rgame_audio_destroy(audio);
    remove(path);
}
END_TEST

START_TEST(a_samples_first_frames_are_at_its_full_level) {
    /* A click has a hard attack. A ramp over its first frames would make it a
     * different sound. */
    rgame_audio *audio = open_offline();
    const char *path = level_wav(0.2, LEVEL);
    rgame_sample *sample = rgame_sample_load(audio, path, NULL, 0);

    rgame_sample_play(sample);

    ck_assert_double_eq_tol(peak_over(audio, 4), LEVEL / 32768.0, 1e-3);

    rgame_sample_destroy(sample);
    rgame_audio_destroy(audio);
    remove(path);
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
    tcase_add_test(tc, a_sound_outlives_the_device_it_came_from);
    tcase_add_test(tc, a_refused_load_leaves_nothing_behind);
    tcase_add_test(tc, loading_the_same_file_many_times_is_fine);

    tcase_add_test(tc, a_played_sample_makes_sound);
    tcase_add_test(tc, a_samples_volume_reaches_the_output);
    tcase_add_test(tc, the_master_volume_reaches_the_output);
    tcase_add_test(tc, a_song_makes_sound_until_it_is_stopped);

    tcase_add_test(tc, a_category_volume_multiplies_every_sound_in_it);
    tcase_add_test(tc, a_song_plays_under_music_and_a_sample_under_effects);
    tcase_add_test(tc, a_sound_moved_to_another_category_takes_that_volume);
    tcase_add_test(tc, a_category_volume_reads_back_and_clamps);
    tcase_add_test(tc, a_category_out_of_range_leaves_a_sound_where_it_was);

    tcase_add_test(tc, resume_carries_on_where_stop_left_the_song);
    tcase_add_test(tc, resume_keeps_the_looping_the_last_play_asked_for);
    tcase_add_test(tc, a_null_device_or_sound_takes_the_new_calls);

    tcase_add_test(tc, a_fade_stepped_once_a_tick_steps_by_one_ticks_share);
    tcase_add_test(tc, a_song_started_again_at_silence_starts_silent);
    tcase_add_test(tc, a_samples_first_frames_are_at_its_full_level);

    suite_add_tcase(suite, tc);
    return suite;
}
