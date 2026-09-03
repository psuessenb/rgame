/*
 * shrink_ogg.c — re-encodes an Ogg Vorbis file smaller, and measures its loop.
 *
 * A development tool, not part of the engine and not built by `make`. It is the
 * companion to make_ogg_fixture.c and needs the same libraries: stb_vorbis (the
 * engine already vendors it) to decode, and libvorbisenc — needed to *run* this
 * and by nothing else — to encode.
 *
 *   cc -o /tmp/shrink_ogg tools/shrink_ogg.c \
 *        -I ext/rgame_core/vendor \
 *        $(pkg-config --cflags --libs vorbisenc vorbis ogg) -lm
 *   /tmp/shrink_ogg in.ogg out.ogg 0.1
 *
 * ## Why this exists
 *
 * Music is by far the largest thing examples/assets/ ships, and the CC0 loops
 * worth using are encoded for listening rather than for a library gem: stereo,
 * 44.1 kHz, ~128 kbps. Everything that directory holds besides audio is 21 KB in
 * total, so a quarter-megabyte loop is not a rounding error — it is the asset
 * set, several times over, shipped to everyone who installs rgame.
 *
 * Mono at a low quality setting is plenty for a background loop in an example,
 * and this is what makes that a one-line change rather than a manual step in an
 * audio editor nobody can reproduce.
 *
 * ## What it deliberately does not do
 *
 * **It does not trim.** A seamless loop is seamless at exactly its own length:
 * the author arranged for the last sample to lead back into the first. Cutting
 * it shorter to save bytes puts an audible seam in the middle of the very thing
 * the file is being shipped to demonstrate. Channels and quality are free to
 * change; length is not.
 *
 * ## The seam figure
 *
 * It reports the discontinuity across the loop point — the jump from the last
 * sample back to the first, against the largest sample-to-sample step found
 * anywhere inside the track. A seam no bigger than the music's own steps is
 * inaudible; one many times larger is a click every time the loop wraps. That
 * turns "loops seamlessly" from a claim on a download page into a number.
 */

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <vorbis/vorbisenc.h>

#define STB_VORBIS_NO_PUSHDATA_API
#include "stb_vorbis.c"

#define CHUNK 1024

/* Writes whatever pages the stream has ready. */
static void flush_pages(ogg_stream_state *stream, FILE *out) {
    ogg_page page;
    while (ogg_stream_pageout(stream, &page) != 0) {
        fwrite(page.header, 1, (size_t)page.header_len, out);
        fwrite(page.body, 1, (size_t)page.body_len, out);
    }
}

/* Pulls every block the encoder has finished and packetises it. */
static void drain_encoder(vorbis_dsp_state *dsp, vorbis_block *block,
                          ogg_stream_state *stream, FILE *out) {
    while (vorbis_analysis_blockout(dsp, block) == 1) {
        vorbis_analysis(block, NULL);
        vorbis_bitrate_addblock(block);

        ogg_packet packet;
        while (vorbis_bitrate_flushpacket(dsp, &packet)) {
            ogg_stream_packetin(stream, &packet);
            flush_pages(stream, out);
        }
    }
}

/* The loop seam, against the track's own largest internal step. */
static void report_seam(const float *mono, int frames) {
    if (frames < 2) {
        return;
    }

    float biggest = 0.0f;
    for (int i = 1; i < frames; i++) {
        float step = fabsf(mono[i] - mono[i - 1]);
        if (step > biggest) {
            biggest = step;
        }
    }

    float seam = fabsf(mono[0] - mono[frames - 1]);
    printf("  loop seam   %.5f, against a largest internal step of %.5f (%.1f%%)\n",
           (double)seam, (double)biggest,
           biggest > 0.0f ? (double)(seam / biggest * 100.0f) : 0.0);
}

int main(int argc, char **argv) {
    if (argc != 4) {
        fprintf(stderr, "usage: %s <in.ogg> <out.ogg> <quality -0.1..1.0>\n", argv[0]);
        return 2;
    }

    int channels = 0;
    int rate = 0;
    short *interleaved = NULL;
    int frames = stb_vorbis_decode_filename(argv[1], &channels, &rate, &interleaved);
    if (frames <= 0) {
        fprintf(stderr, "cannot decode %s\n", argv[1]);
        return 1;
    }

    /* Downmix to mono by averaging. A background loop is not spatial, and the
     * channel that would be dropped by simply taking the left one often carries
     * half the arrangement. */
    float *mono = malloc((size_t)frames * sizeof(float));
    if (!mono) {
        fprintf(stderr, "out of memory\n");
        return 1;
    }
    for (int i = 0; i < frames; i++) {
        float sum = 0.0f;
        for (int c = 0; c < channels; c++) {
            sum += (float)interleaved[(size_t)i * channels + c] / 32768.0f;
        }
        mono[i] = sum / (float)channels;
    }
    free(interleaved);

    printf("read %s: %.2fs, %d channels, %d Hz\n",
           argv[1], (double)frames / rate, channels, rate);
    report_seam(mono, frames);

    vorbis_info info;
    vorbis_info_init(&info);
    if (vorbis_encode_init_vbr(&info, 1, rate, (float)atof(argv[3])) != 0) {
        fprintf(stderr, "vorbis_encode_init_vbr failed\n");
        return 1;
    }

    vorbis_comment comment;
    vorbis_comment_init(&comment);
    vorbis_comment_add_tag(&comment, "ENCODER", "rgame tools/shrink_ogg.c");

    vorbis_dsp_state dsp;
    vorbis_block block;
    vorbis_analysis_init(&dsp, &info);
    vorbis_block_init(&dsp, &block);

    /* A fixed serial number, so re-running this with no other change produces
     * the same bytes and does not show up as a diff. */
    ogg_stream_state stream;
    ogg_stream_init(&stream, 20260903);

    FILE *out = fopen(argv[2], "wb");
    if (!out) {
        fprintf(stderr, "cannot write %s\n", argv[2]);
        return 1;
    }

    ogg_packet id, comments, code;
    vorbis_analysis_headerout(&dsp, &comment, &id, &comments, &code);
    ogg_stream_packetin(&stream, &id);
    ogg_stream_packetin(&stream, &comments);
    ogg_stream_packetin(&stream, &code);

    /* The headers must end on their own page, so the audio starts on a fresh
     * one — players and decoders are entitled to assume that. */
    ogg_page page;
    while (ogg_stream_flush(&stream, &page) != 0) {
        fwrite(page.header, 1, (size_t)page.header_len, out);
        fwrite(page.body, 1, (size_t)page.body_len, out);
    }

    for (int written = 0; written < frames;) {
        int count = frames - written < CHUNK ? frames - written : CHUNK;
        float **buffer = vorbis_analysis_buffer(&dsp, count);

        for (int i = 0; i < count; i++) {
            buffer[0][i] = mono[written + i];
        }

        vorbis_analysis_wrote(&dsp, count);
        drain_encoder(&dsp, &block, &stream, out);
        written += count;
    }

    /* A zero-length write is how the encoder is told the stream has ended. */
    vorbis_analysis_wrote(&dsp, 0);
    drain_encoder(&dsp, &block, &stream, out);

    fclose(out);
    ogg_stream_clear(&stream);
    vorbis_block_clear(&block);
    vorbis_dsp_clear(&dsp);
    vorbis_comment_clear(&comment);
    vorbis_info_clear(&info);
    free(mono);

    printf("wrote %s: %.2fs, 1 channel, %d Hz, quality %s\n",
           argv[2], (double)frames / rate, rate, argv[3]);
    return 0;
}
