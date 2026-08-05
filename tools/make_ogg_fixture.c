/*
 * make_ogg_fixture.c — writes the Ogg Vorbis file the audio specs decode.
 *
 * A development tool, not part of the engine and not built by `make`. It exists
 * because the other suites can generate their own fixtures and the audio one
 * cannot: `spec_core/support/png_fixture.rb` writes PNGs with Ruby's zlib, and
 * the font tests use the font the engine ships, but there is no Ogg Vorbis
 * encoder in Ruby's standard library and stb_vorbis only decodes.
 *
 * So the fixture is generated once, here, and committed. libvorbisenc is needed
 * to *run* this and by nothing else — the engine itself links no vorbis library
 * at all.
 *
 *   cc -o /tmp/make_ogg_fixture tools/make_ogg_fixture.c \
 *        $(pkg-config --cflags --libs vorbisenc vorbis ogg) -lm
 *   /tmp/make_ogg_fixture spec_core/fixtures/tone.ogg
 *
 * What it writes is deliberately asymmetric: a quarter second of stereo, 440 Hz
 * in the left channel and 880 Hz in the right. A decoder that loses a channel,
 * swaps the two, or collapses to mono produces something a test can see.
 */

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <vorbis/vorbisenc.h>

/* -std=c17 asks for strict ISO C, which hides M_PI. One line, portable. */
#define RGAME_TWO_PI 6.283185307179586

#define SAMPLE_RATE 44100
#define CHANNELS 2
#define SECONDS 0.25f
#define LEFT_HZ 440.0
#define RIGHT_HZ 880.0
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

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: %s <output.ogg>\n", argv[0]);
        return 2;
    }

    vorbis_info info;
    vorbis_info_init(&info);
    /* Quality 0.1: small file, and nothing here cares how it sounds. */
    if (vorbis_encode_init_vbr(&info, CHANNELS, SAMPLE_RATE, 0.1f) != 0) {
        fprintf(stderr, "vorbis_encode_init_vbr failed\n");
        return 1;
    }

    vorbis_comment comment;
    vorbis_comment_init(&comment);
    vorbis_comment_add_tag(&comment, "ENCODER", "rgame tools/make_ogg_fixture.c");

    vorbis_dsp_state dsp;
    vorbis_block block;
    vorbis_analysis_init(&dsp, &info);
    vorbis_block_init(&dsp, &block);

    /* A fixed serial number, so regenerating the fixture with no other change
     * produces the same bytes and does not show up as a diff. */
    ogg_stream_state stream;
    ogg_stream_init(&stream, 20260805);

    FILE *out = fopen(argv[1], "wb");
    if (!out) {
        fprintf(stderr, "cannot write %s\n", argv[1]);
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

    long total = (long)(SECONDS * SAMPLE_RATE);
    for (long written = 0; written < total;) {
        long count = total - written < CHUNK ? total - written : CHUNK;
        float **buffer = vorbis_analysis_buffer(&dsp, (int)count);

        for (long i = 0; i < count; i++) {
            double t = (double)(written + i) / SAMPLE_RATE;
            buffer[0][i] = (float)(0.5 * sin(RGAME_TWO_PI * LEFT_HZ * t));
            buffer[1][i] = (float)(0.5 * sin(RGAME_TWO_PI * RIGHT_HZ * t));
        }

        vorbis_analysis_wrote(&dsp, (int)count);
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

    printf("wrote %s: %.2fs, %d channels, %d Hz\n", argv[1], SECONDS, CHANNELS, SAMPLE_RATE);
    return 0;
}
