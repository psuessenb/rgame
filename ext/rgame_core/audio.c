/*
 * audio.c — the sound device, and the two kinds of sound.
 *
 * Layer 3 in CLAUDE.md's scheme, and by far the thinnest of the three: the
 * mixing, the voices, the resampling and the device thread are all miniaudio's,
 * and Ogg Vorbis is vorbis_decoder.c's. What is left here is opening the
 * device, loading two kinds of file, and the small amount of policy the engine
 * has an opinion about.
 *
 * Unusually for a layer-3 file it is properly *tested* rather than merely
 * looked at, because miniaudio's null backend is a real device that consumes
 * frames on a timer and produces silence. `test/test_audio.c` drives all of
 * this with no sound card — see the note on the fallback in
 * `rgame_audio_create`.
 *
 * ---------------------------------------------------------------------------
 * Why samples and songs are different types
 * ---------------------------------------------------------------------------
 *
 * A footstep is played fifty times a minute and must overlap itself; a music
 * track plays once, loops, and gets stopped. Those want opposite things from
 * the mixer:
 *
 *   sample   decoded into memory once, then a fresh voice per play, each one
 *            cleaning itself up. No handle, so nothing to stop or query.
 *   song     one long-lived voice reading from disk, which can be started,
 *            stopped and asked whether it is playing.
 *
 * One type with a flag would have to answer `playing?` for a sound that has
 * five voices or none, and the honest answer is that the question does not
 * apply. Two types, and the question cannot be asked.
 */

#include "rgame/core.h"

#include "audio_internal.h"
#include "vendor/miniaudio.h"
#include "vorbis_decoder.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct rgame_audio {
    ma_resource_manager resources;
    ma_engine engine;
};

struct rgame_sample {
    rgame_audio *audio;
    /* The resource manager is keyed by path, so the path *is* the handle for
     * playback. */
    char *path;
    /*
     * A voice that is never started. Its only jobs are to fail loudly at load
     * time if the file is not a sound, and to hold the resource manager's
     * decoded copy alive for as long as this sample exists — the manager
     * reference counts by path, so every `play` below finds the data already
     * decoded instead of decoding again.
     */
    ma_sound decoded;
    /*
     * Every voice of this sample plays into this group, which exists so that
     * volume has somewhere to live. A fire-and-forget voice hands back no
     * handle to set anything on, so per-*play* volume is not available; per
     * sample is, and it reaches voices already sounding.
     */
    ma_sound_group group;
};

struct rgame_song {
    rgame_audio *audio;
    ma_sound sound;
};

/* See rgame_audio_live_sounds. */
static long live_sounds = 0;

long rgame_audio_live_sounds(void) {
    return live_sounds;
}

static void set_error(char *err, size_t err_size, const char *format, const char *detail) {
    if (err && err_size > 0) {
        snprintf(err, err_size, format, detail);
    }
}

/* Volume is a gain, so above 1.0 amplifies and is the caller's business; below
 * zero is not a volume at all. */
static float clamp_volume(float volume) {
    return volume < 0.0f ? 0.0f : volume;
}

/* ------------------------------------------------------------------------- *
 * The device
 * ------------------------------------------------------------------------- */

/* Shared by the real constructor and the offline one below, which differ only
 * in whether a device is opened. */
static rgame_audio *create_audio(int offline, unsigned int sample_rate, char *err,
                                 size_t err_size) {
    rgame_audio *audio = calloc(1, sizeof(rgame_audio));
    if (!audio) {
        set_error(err, err_size, "%s", "out of memory");
        return NULL;
    }

    /*
     * The resource manager is where the vorbis backend gets registered, and
     * registering it here is what makes every .ogg in the engine readable —
     * miniaudio cannot read one otherwise. Everything that loads a file goes
     * through this manager.
     */
    static ma_decoding_backend_vtable *decoders[] = { &rgame_vorbis_decoding_backend };

    ma_resource_manager_config resources = ma_resource_manager_config_init();
    resources.ppCustomDecodingBackendVTables = decoders;
    resources.customDecodingBackendCount = 1;


    if (ma_resource_manager_init(&resources, &audio->resources) != MA_SUCCESS) {
        free(audio);
        set_error(err, err_size, "%s", "could not start the audio resource manager");
        return NULL;
    }

    /*
     * No explicit backend list: miniaudio tries the real ones in order and
     * falls back to a null device when none of them can open. So a machine with
     * no sound card — a build server, a container — gets a working engine that
     * plays silence rather than an error a game has to handle. Verified: with
     * ALSA and PulseAudio unavailable, the chosen backend is "Null".
     */
    ma_engine_config engine = ma_engine_config_init();
    engine.pResourceManager = &audio->resources;
    if (offline) {
        /* No device at all: the caller pumps the mixer. Channels and rate have
         * to be stated, because without a device there is nothing to ask. */
        engine.noDevice = MA_TRUE;
        engine.channels = 2;
        engine.sampleRate = sample_rate;
    }

    if (ma_engine_init(&engine, &audio->engine) != MA_SUCCESS) {
        ma_resource_manager_uninit(&audio->resources);
        free(audio);
        set_error(err, err_size, "%s", "could not start the audio engine");
        return NULL;
    }

    return audio;
}

rgame_audio *rgame_audio_create(char *err, size_t err_size) {
    return create_audio(0, 0, err, err_size);
}

rgame_audio *rgame_audio_create_offline(unsigned int sample_rate, char *err, size_t err_size) {
    return create_audio(1, sample_rate, err, err_size);
}

unsigned int rgame_audio_read(rgame_audio *audio, float *out, unsigned int frames) {
    if (!audio || !out) {
        return 0;
    }

    ma_uint64 read = 0;
    ma_engine_read_pcm_frames(&audio->engine, out, frames, &read);
    return (unsigned int)read;
}

void rgame_audio_destroy(rgame_audio *audio) {
    if (!audio) {
        return;
    }

    /* The engine first: it owns the device thread, and the resource manager
     * underneath is still holding the data that thread may be reading. */
    ma_engine_uninit(&audio->engine);
    ma_resource_manager_uninit(&audio->resources);
    free(audio);
}

void rgame_audio_set_volume(rgame_audio *audio, float volume) {
    if (audio) {
        ma_engine_set_volume(&audio->engine, clamp_volume(volume));
    }
}

float rgame_audio_volume(const rgame_audio *audio) {
    /* ma_engine_get_volume takes a non-const pointer for no reason this call
     * can honour; the cast keeps the query const for callers. */
    return audio ? ma_engine_get_volume((ma_engine *)&audio->engine) : 0.0f;
}

const char *rgame_audio_backend(const rgame_audio *audio) {
    if (!audio) {
        return "none";
    }

    ma_device *device = ma_engine_get_device((ma_engine *)&audio->engine);
    return device ? ma_get_backend_name(device->pContext->backend) : "none";
}

/*
 * Is this a file the engine can actually play?
 *
 * Asked *before* handing the path to the resource manager, and the reason is a
 * bug in miniaudio 0.11.25: when a load fails, `ma_resource_manager_data_buffer_node_acquire`
 * frees the node and then reads a field of it a few lines later
 * (miniaudio.h:70918 and :70926). Every rejected file is therefore a
 * use-after-free — found by running these tests under AddressSanitizer, and
 * reachable from anything that loads a decoded sound, including
 * `ma_sound_init_from_file`.
 *
 * Checking first means the failing path is never entered: a file that is not a
 * sound is turned away here, and one that is loads successfully. Patching the
 * vendored copy would work until the next update silently dropped the fix, so
 * this goes around it instead — worth re-testing when miniaudio is bumped.
 *
 * The check is not merely a formality either: it uses the same decoders the
 * real load will, so "readable here" and "readable there" cannot disagree.
 */
static int file_is_playable(const char *path) {
    static ma_decoding_backend_vtable *decoders[] = { &rgame_vorbis_decoding_backend };

    ma_decoder_config config = ma_decoder_config_init_default();
    config.ppCustomBackendVTables = decoders;
    config.customBackendCount = 1;

    ma_decoder decoder;
    if (ma_decoder_init_file(path, &config, &decoder) != MA_SUCCESS) {
        return 0;
    }

    ma_decoder_uninit(&decoder);
    return 1;
}

/* ------------------------------------------------------------------------- *
 * Samples
 * ------------------------------------------------------------------------- */

rgame_sample *rgame_sample_load(rgame_audio *audio, const char *path, char *err,
                                size_t err_size) {
    if (!audio || !path) {
        set_error(err, err_size, "%s", "no audio device or path given");
        return NULL;
    }

    rgame_sample *sample = calloc(1, sizeof(rgame_sample));
    if (!sample) {
        set_error(err, err_size, "%s", "out of memory");
        return NULL;
    }

    /* Turned away before the resource manager ever sees it — see
     * file_is_playable for why that order matters. */
    if (!file_is_playable(path)) {
        free(sample);
        set_error(err, err_size, "could not load %s", path);
        return NULL;
    }

    /*
     * Decoded now, synchronously, rather than on first play: the decode then
     * does not happen during a frame, and the sound below holds the resource
     * manager's copy alive so every `play` finds it already done.
     */
    if (ma_sound_init_from_file(&audio->engine, path, MA_SOUND_FLAG_DECODE, NULL, NULL,
                                &sample->decoded) != MA_SUCCESS) {
        free(sample);
        set_error(err, err_size, "could not load %s", path);
        return NULL;
    }

    if (ma_sound_group_init(&audio->engine, 0, NULL, &sample->group) != MA_SUCCESS) {
        ma_sound_uninit(&sample->decoded);
        free(sample);
        set_error(err, err_size, "%s", "could not create a mixer group for the sample");
        return NULL;
    }

    sample->path = malloc(strlen(path) + 1);
    if (!sample->path) {
        ma_sound_group_uninit(&sample->group);
        ma_sound_uninit(&sample->decoded);
        free(sample);
        set_error(err, err_size, "%s", "out of memory");
        return NULL;
    }
    strcpy(sample->path, path);

    sample->audio = audio;
    live_sounds++;
    return sample;
}

void rgame_sample_destroy(rgame_sample *sample) {
    if (!sample) {
        return;
    }

    /*
     * Stop the group before tearing it down: its voices are nodes attached to
     * it, and a voice still sounding when its group goes is reading through
     * something being freed on another thread.
     *
     * `ma_sound_group_uninit` turns out to handle that itself, so removing the
     * stop survives the suite and the sanitizer. Kept anyway: "the thing is
     * silent before it is freed" is one line, and relying on a teardown
     * function to also be a stop function is the kind of assumption that holds
     * until a version bump.
     */
    ma_sound_group_stop(&sample->group);
    ma_sound_group_uninit(&sample->group);

    /* Releases this sample's claim on the decoded data. Other samples of the
     * same file hold their own, so the last one out frees it. */
    ma_sound_uninit(&sample->decoded);
    free(sample->path);
    free(sample);
    live_sounds--;
}

void rgame_sample_play(rgame_sample *sample) {
    if (!sample) {
        return;
    }

    /*
     * Fire and forget: the engine spawns a voice from the already-decoded data,
     * plays it, and cleans it up itself. Calling this again while the last one
     * is still sounding gives a second voice rather than restarting the first —
     * which is the whole difference between a sample and a song.
     *
     * The return value is ignored deliberately. Running out of voices is not
     * something a game can do anything useful about mid-frame, and a footstep
     * that does not play is better than an exception during `update`.
     */
    ma_engine_play_sound(&sample->audio->engine, sample->path, &sample->group);
}

void rgame_sample_set_volume(rgame_sample *sample, float volume) {
    if (sample) {
        ma_sound_group_set_volume(&sample->group, clamp_volume(volume));
    }
}

float rgame_sample_volume(const rgame_sample *sample) {
    return sample ? ma_sound_group_get_volume((ma_sound_group *)&sample->group) : 0.0f;
}

/* ------------------------------------------------------------------------- *
 * Songs
 * ------------------------------------------------------------------------- */

rgame_song *rgame_song_load(rgame_audio *audio, const char *path, char *err, size_t err_size) {
    if (!audio || !path) {
        set_error(err, err_size, "%s", "no audio device or path given");
        return NULL;
    }

    rgame_song *song = calloc(1, sizeof(rgame_song));
    if (!song) {
        set_error(err, err_size, "%s", "out of memory");
        return NULL;
    }

    /* Checked first, as samples are. Streaming happens to take a different path
     * through miniaudio and does not trip the bug described above, but "some
     * loads validate first and others do not" is a distinction nobody should
     * have to remember. */
    if (!file_is_playable(path)) {
        free(song);
        set_error(err, err_size, "could not load %s", path);
        return NULL;
    }

    /*
     * Streamed, so a long track costs a buffer rather than its whole decoded
     * length in memory — thirty megabytes for three minutes of CD-quality
     * stereo, measured, if it were decoded.
     *
     * No test can see the difference: with a quarter-second fixture the two
     * behave identically, and the mutation to MA_SOUND_FLAG_DECODE survives.
     * What it protects is a number nobody measures until a player's machine
     * starts swapping.
     */
    if (ma_sound_init_from_file(&audio->engine, path, MA_SOUND_FLAG_STREAM, NULL, NULL,
                                &song->sound) != MA_SUCCESS) {
        free(song);
        set_error(err, err_size, "could not load %s", path);
        return NULL;
    }

    song->audio = audio;
    live_sounds++;
    return song;
}

void rgame_song_destroy(rgame_song *song) {
    if (!song) {
        return;
    }

    ma_sound_uninit(&song->sound);
    free(song);
    live_sounds--;
}

void rgame_song_play(rgame_song *song, int looping) {
    if (!song) {
        return;
    }

    ma_sound_set_looping(&song->sound, looping ? MA_TRUE : MA_FALSE);

    /*
     * Rewind first. A song that played to its end sits at the end, and starting
     * it again without seeking produces nothing at all — the failure being
     * "the music stopped working after the first time", which is a miserable
     * one to track down. It also makes `stop` then `play` mean "from the
     * beginning" rather than "resume", which is what the layer being replaced
     * did.
     *
     * Not covered by a test, and the mutation that removes it survives.
     * Observing it needs a song played nearly to its end, and a streamed sound
     * cannot be driven that far by the offline test device — it refills its
     * buffers on a thread that a tight pumping loop starves. Checking it would
     * mean exposing a playback-position query that nothing else wants. Verified
     * by ear instead: `ruby ext/rgame_core/example.rb <a sound file>` binds
     * Return to stop and start a song, so pressing it twice is the check. The
     * C driver has no audio in it — a sound file is a thing you bring.
     */
    ma_sound_seek_to_pcm_frame(&song->sound, 0);
    ma_sound_start(&song->sound);
}

void rgame_song_stop(rgame_song *song) {
    if (song) {
        /* Stop leaves the playhead where it is; `play` rewinds, so together
         * they mean "start from the beginning" rather than "resume". That is
         * what the layer being replaced did. */
        ma_sound_stop(&song->sound);
    }
}

int rgame_song_playing(const rgame_song *song) {
    return song && ma_sound_is_playing((ma_sound *)&song->sound) ? 1 : 0;
}

int rgame_song_looping(const rgame_song *song) {
    return song && ma_sound_is_looping((ma_sound *)&song->sound) ? 1 : 0;
}

void rgame_song_set_volume(rgame_song *song, float volume) {
    if (song) {
        ma_sound_set_volume(&song->sound, clamp_volume(volume));
    }
}

float rgame_song_volume(const rgame_song *song) {
    return song ? ma_sound_get_volume((ma_sound *)&song->sound) : 0.0f;
}
