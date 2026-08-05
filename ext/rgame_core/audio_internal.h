#ifndef RGAME_AUDIO_INTERNAL_H
#define RGAME_AUDIO_INTERNAL_H

#include <stddef.h>

#include "rgame/core.h"

/*
 * The counter tests assert against, kept out of the public header the same way
 * the texture and font-page counters are.
 *
 * A leaked sound is invisible: nothing sounds wrong, nothing gets slower, and
 * memory grows over an hour of play. Counting the live ones makes "the sound
 * went away when the game dropped it" something a spec can state.
 *
 * Single-threaded, like the rest of the engine's bookkeeping.
 */
long rgame_audio_live_sounds(void);

/*
 * An audio device with no device behind it: nothing is sent anywhere, and the
 * caller pumps the mixer by hand and gets the samples back.
 *
 * This is the audio equivalent of reading the framebuffer, and it exists for
 * the same reason. Everything else a test can check about sound is a
 * transition — it says it is playing, it says it stopped — and a stack that
 * reported all of those correctly while emitting silence would pass every one
 * of them. Silence is also exactly what a broken audio stack produces, so
 * "assert on what actually comes out" is worth more here than almost anywhere.
 *
 * Test-only, hence its place in this header rather than in core.h. A game wants
 * the real constructor, which opens a real device.
 */
rgame_audio *rgame_audio_create_offline(unsigned int sample_rate, char *err, size_t err_size);

/*
 * Mixes the next `frames` frames of stereo output into `out`, which must have
 * room for `frames * 2` floats. Returns the number of frames written.
 *
 * Only meaningful on a device made by rgame_audio_create_offline; a real device
 * is pumped by its own thread and there is nothing here to read.
 */
unsigned int rgame_audio_read(rgame_audio *audio, float *out, unsigned int frames);

#endif /* RGAME_AUDIO_INTERNAL_H */
