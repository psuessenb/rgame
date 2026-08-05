/*
 * miniaudio_impl.c — the one translation unit that instantiates miniaudio.
 *
 * Same shape as stb_image_impl.c and stb_truetype_impl.c: a single-header
 * library emits its function bodies only where the implementation macro is
 * defined, so exactly one file defines it and contains nothing else. That lets
 * audio.c include the header the ordinary way, and lets the build relax
 * -Wall -Wextra for the vendored code and nothing else.
 *
 * ---------------------------------------------------------------------------
 * Why the feature macros are here and not in the Makefile
 * ---------------------------------------------------------------------------
 *
 * Every one of them changes what the engine can *do*, not how it is built —
 * which formats it reads, which sound systems it can talk to. Put in a build
 * flag they would have to be repeated in the root Makefile and in extconf.rb,
 * and the day the two disagreed the standalone binary and the gem would support
 * different audio formats. Here there is one copy and no way to disagree.
 *
 * Licence: miniaudio is public domain / MIT-0. See vendor/README.md.
 */

/*
 * Formats. Ogg Vorbis is what the games use; WAV comes free with miniaudio and
 * is convenient for test fixtures, which can be written from Ruby in twenty
 * lines. MP3 and FLAC are compiled out — measured at 215 KB of object code
 * saved together with the encoders and generators below, and every format left
 * in is another parser reachable from whatever files a game loads.
 *
 * Vorbis is not in this list because miniaudio cannot read it at all; that is
 * what vorbis_decoder.c is for.
 */
#define MA_NO_FLAC
#define MA_NO_MP3

/* The engine plays sound; it never records or writes it, and it has no use for
 * miniaudio's waveform and noise generators. */
#define MA_NO_ENCODING
#define MA_NO_GENERATION

/*
 * Sound systems, named explicitly rather than taking the default set.
 *
 * ALSA and PulseAudio cover Linux; miniaudio loads whichever is present *at
 * runtime* with dlopen, which is the property that makes audio cost this
 * project no new system dependency. On Windows and macOS the platform backends
 * come in regardless of this list.
 *
 * MA_ENABLE_NULL is not an afterthought: it is a device that consumes frames on
 * a timer and produces silence, and it is what lets the whole audio stack —
 * loading, mixing, looping, `playing?` — be tested with no sound card, in
 * `make test` and in CI. Compiling it out would take the test suite with it.
 */
#define MA_ENABLE_ONLY_SPECIFIC_BACKENDS
#define MA_ENABLE_ALSA
#define MA_ENABLE_PULSEAUDIO
#define MA_ENABLE_COREAUDIO
#define MA_ENABLE_WASAPI
#define MA_ENABLE_NULL

#define MINIAUDIO_IMPLEMENTATION
#include "vendor/miniaudio.h"
