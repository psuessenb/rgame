/*
 * vorbis_decoder.c — a miniaudio decoding backend over stb_vorbis.
 * See vorbis_decoder.h for why it exists and why it has two entry points.
 */

#include "audio/vorbis_decoder.h"

/* Declarations only. The code lives in stb_vorbis_impl.c, which is the one
 * translation unit compiled without the project's warning flags; including it
 * whole here would both duplicate every symbol and drag third-party code
 * through -Wall -Wextra. */
#define STB_VORBIS_HEADER_ONLY
#include "vendor/stb_vorbis.c"

/*
 * One open ogg stream, as miniaudio sees it.
 *
 * `ma_data_source_base` must come first: miniaudio casts the pointer it is
 * handed straight to its own base type, so anything before it would be read as
 * the base and the first call would go somewhere unfortunate.
 */
typedef struct {
    ma_data_source_base base;
    stb_vorbis *vorbis;
    ma_uint32 channels;
    ma_uint32 sample_rate;
    /* The compressed file, when it was opened from memory. stb_vorbis keeps
     * reading from this for the life of the stream, so it is freed in uninit
     * and not before. NULL when opened by filename. */
    void *compressed;
} rgame_vorbis_stream;

/* ------------------------------------------------------------------------- *
 * The data source: reading, seeking, and answering questions about the stream
 * ------------------------------------------------------------------------- */

static ma_result vorbis_read(ma_data_source *source, void *out, ma_uint64 frames_wanted,
                             ma_uint64 *frames_read) {
    rgame_vorbis_stream *stream = (rgame_vorbis_stream *)source;
    float *destination = (float *)out;
    ma_uint64 filled = 0;

    /*
     * Keep going until the buffer is full or the file really has run out.
     *
     * One call is not enough: stb_vorbis decodes a packet at a time and
     * routinely hands back fewer frames than were asked for, in the middle of a
     * perfectly healthy file. Callers read a short read as the end — miniaudio's
     * streaming path does exactly that, marking the stream finished when a page
     * comes back under-filled — so passing stb's partial counts straight up
     * makes a streamed song stop after its first packet-run and never loop.
     * That was a real bug here, and it looked like "looping does not work".
     *
     * stb counts in *samples*, one per channel per frame, while miniaudio counts
     * in frames; the multiply below is that conversion, and getting it wrong
     * plays everything at the wrong speed.
     */
    while (filled < frames_wanted) {
        ma_uint64 remaining = frames_wanted - filled;
        int got = stb_vorbis_get_samples_float_interleaved(
            stream->vorbis, (int)stream->channels, destination + (filled * stream->channels),
            (int)(remaining * stream->channels));

        if (got <= 0) {
            break; /* genuinely out of audio */
        }
        filled += (ma_uint64)got;
    }

    ma_uint64 got = filled;
    *frames_read = got;

    /*
     * MA_AT_END rather than an error: running out is how a sound ends.
     *
     * Both halves of this are unobservable through miniaudio, and mutating
     * either survives the suite — measured. miniaudio decides end-of-stream
     * from `frames_read`, so a source that always claimed MA_SUCCESS still
     * makes the decoder report MA_AT_END, and one that always claimed
     * MA_AT_END is ignored while frames keep arriving. It says the true thing
     * anyway: the contract is what a data source is supposed to report, and
     * the next thing to read this code should not have to rediscover that
     * miniaudio happens not to look.
     */
    return got > 0 ? MA_SUCCESS : MA_AT_END;
}

static ma_result vorbis_seek(ma_data_source *source, ma_uint64 frame) {
    rgame_vorbis_stream *stream = (rgame_vorbis_stream *)source;
    return stb_vorbis_seek(stream->vorbis, (unsigned int)frame) ? MA_SUCCESS : MA_ERROR;
}

static ma_result vorbis_data_format(ma_data_source *source, ma_format *format,
                                    ma_uint32 *channels, ma_uint32 *sample_rate,
                                    ma_channel *channel_map, size_t channel_map_capacity) {
    rgame_vorbis_stream *stream = (rgame_vorbis_stream *)source;

    if (format) {
        /* Floats, because that is what stb_vorbis hands back and what
         * miniaudio's graph works in — no conversion in the middle. */
        *format = ma_format_f32;
    }
    if (channels) {
        *channels = stream->channels;
    }
    if (sample_rate) {
        *sample_rate = stream->sample_rate;
    }
    if (channel_map) {
        ma_channel_map_init_standard(ma_standard_channel_map_default, channel_map,
                                     channel_map_capacity, stream->channels);
    }
    return MA_SUCCESS;
}

static ma_result vorbis_cursor(ma_data_source *source, ma_uint64 *cursor) {
    rgame_vorbis_stream *stream = (rgame_vorbis_stream *)source;
    *cursor = (ma_uint64)stb_vorbis_get_sample_offset(stream->vorbis);
    return MA_SUCCESS;
}

static ma_result vorbis_length(ma_data_source *source, ma_uint64 *length) {
    rgame_vorbis_stream *stream = (rgame_vorbis_stream *)source;
    *length = (ma_uint64)stb_vorbis_stream_length_in_samples(stream->vorbis);
    return MA_SUCCESS;
}

static ma_data_source_vtable vorbis_data_source_vtable = {
    vorbis_read, vorbis_seek, vorbis_data_format, vorbis_cursor, vorbis_length,
    NULL, /* onSetLooping: miniaudio handles looping above this level */
    0
};

/* ------------------------------------------------------------------------- *
 * Opening
 * ------------------------------------------------------------------------- */

/* Shared tail of both entry points: an open stb handle becomes a data source. */
static ma_result finish_open(rgame_vorbis_stream *stream, void *compressed,
                             const ma_allocation_callbacks *allocations,
                             ma_data_source **out) {
    stb_vorbis_info info = stb_vorbis_get_info(stream->vorbis);
    stream->channels = (ma_uint32)info.channels;
    stream->sample_rate = info.sample_rate;
    stream->compressed = compressed;

    ma_data_source_config config = ma_data_source_config_init();
    config.vtable = &vorbis_data_source_vtable;

    if (ma_data_source_init(&config, &stream->base) != MA_SUCCESS) {
        stb_vorbis_close(stream->vorbis);
        ma_free(compressed, allocations);
        ma_free(stream, allocations);
        return MA_ERROR;
    }

    *out = (ma_data_source *)stream;
    return MA_SUCCESS;
}

static ma_result vorbis_init_file(void *user_data, const char *path,
                                  const ma_decoding_backend_config *config,
                                  const ma_allocation_callbacks *allocations,
                                  ma_data_source **out) {
    (void)user_data;
    (void)config;

    rgame_vorbis_stream *stream = ma_malloc(sizeof(rgame_vorbis_stream), allocations);
    if (!stream) {
        return MA_OUT_OF_MEMORY;
    }

    int error = 0;
    stream->vorbis = stb_vorbis_open_filename(path, &error, NULL);
    if (!stream->vorbis) {
        ma_free(stream, allocations);
        /* Not an error worth distinguishing: a missing file and a file that is
         * not an ogg both mean "this is not a sound", and the caller reports
         * the path either way. */
        return MA_INVALID_FILE;
    }

    return finish_open(stream, NULL, allocations, out);
}

/*
 * The callback path, which is the one `ma_engine` uses.
 *
 * stb_vorbis cannot read through callbacks, so the whole compressed file is
 * pulled in and opened from memory. See the header for why that is the right
 * trade against the pushdata API.
 */
static ma_result vorbis_init(void *user_data, ma_read_proc on_read, ma_seek_proc on_seek,
                             ma_tell_proc on_tell, void *read_seek_tell_user_data,
                             const ma_decoding_backend_config *config,
                             const ma_allocation_callbacks *allocations,
                             ma_data_source **out) {
    (void)user_data;
    (void)config;

    /* Seek to the end to find the size, then back. There is no "how big is
     * this" callback; this is the only way to ask. */
    if (on_seek(read_seek_tell_user_data, 0, ma_seek_origin_end) != MA_SUCCESS) {
        return MA_ERROR;
    }
    ma_int64 size = 0;
    /* The `size <= 0` half is belt and braces: stb_vorbis refuses a zero-length
     * buffer on its own, so removing it survives the suite. It stays because
     * `ma_malloc(0)` and a zero-length read are not worth reasoning about at
     * every call site downstream. */
    if (on_tell(read_seek_tell_user_data, &size) != MA_SUCCESS || size <= 0) {
        return MA_ERROR;
    }
    if (on_seek(read_seek_tell_user_data, 0, ma_seek_origin_start) != MA_SUCCESS) {
        return MA_ERROR;
    }

    void *compressed = ma_malloc((size_t)size, allocations);
    if (!compressed) {
        return MA_OUT_OF_MEMORY;
    }

    size_t got = 0;
    if (on_read(read_seek_tell_user_data, compressed, (size_t)size, &got) != MA_SUCCESS ||
        got != (size_t)size) {
        ma_free(compressed, allocations);
        return MA_ERROR;
    }

    rgame_vorbis_stream *stream = ma_malloc(sizeof(rgame_vorbis_stream), allocations);
    if (!stream) {
        ma_free(compressed, allocations);
        return MA_OUT_OF_MEMORY;
    }

    int error = 0;
    stream->vorbis = stb_vorbis_open_memory(compressed, (int)size, &error, NULL);
    if (!stream->vorbis) {
        ma_free(compressed, allocations);
        ma_free(stream, allocations);
        return MA_INVALID_FILE;
    }

    /* `compressed` is handed over here, not freed: stb_vorbis keeps pointing
     * into it. */
    return finish_open(stream, compressed, allocations, out);
}

static void vorbis_uninit(void *user_data, ma_data_source *source,
                          const ma_allocation_callbacks *allocations) {
    (void)user_data;
    if (!source) {
        return;
    }

    rgame_vorbis_stream *stream = (rgame_vorbis_stream *)source;

    /* Close first, free second. Swapping them survives the suite and even the
     * sanitizer, because stb_vorbis_close only releases its own allocations and
     * never looks at the input buffer again — but that is a fact about today's
     * stb_vorbis, not a promise, and the order that cannot be wrong costs
     * nothing. */
    stb_vorbis_close(stream->vorbis);
    ma_free(stream->compressed, allocations); /* NULL when opened by filename */
    ma_data_source_uninit(&stream->base);
    ma_free(stream, allocations);
}

/*
 * Both entry points, though only one is strictly required: with `onInitFile`
 * absent miniaudio falls back to opening the file itself and calling `onInit`,
 * so removing it survives the suite. It stays because that fallback buffers the
 * whole compressed file, and opening by name lets stb_vorbis read from disk
 * instead — which for a music track is a few megabytes not held in memory.
 */
ma_decoding_backend_vtable rgame_vorbis_decoding_backend = {
    vorbis_init,
    vorbis_init_file,
    NULL, /* onInitFileW: the engine has no wide-character paths */
    NULL, /* onInitMemory: nothing loads an ogg from a Ruby string yet */
    vorbis_uninit
};
