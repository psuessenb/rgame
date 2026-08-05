#include <check.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "text/font.h"
#include "suites.h"

/*
 * Layer-1 tests for font.c, run against the font the engine ships.
 *
 * That is worth a note: these are not fixture-driven or approximate. Because
 * `lib/rgame/fonts/LiberationSans-Regular.ttf` is part of the project, the
 * suite can assert on the real advances of real glyphs — that `i` is narrower
 * than `W`, that `AV` kerns tighter than `A` then `V`, that a space has an
 * advance and no ink. A font resolved from the system at runtime, the way the
 * layer being replaced does it, would make every one of these
 * machine-dependent.
 *
 * The path is relative to the repository root, which is where `make test` runs
 * the binary from.
 */

#define FONT_PATH "lib/rgame/fonts/LiberationSans-Regular.ttf"
#define TEST_PIXEL_HEIGHT 18
#define TOL 1e-3f

static unsigned char *font_bytes = NULL;
static size_t font_length = 0;

/* Read once for the whole suite: Check forks per test, so this happens in the
 * parent and every test inherits the buffer. */
static void load_font_file(void) {
    FILE *file = fopen(FONT_PATH, "rb");
    ck_assert_msg(file != NULL, "cannot open " FONT_PATH " (run make test from the repo root)");

    ck_assert_int_eq(fseek(file, 0, SEEK_END), 0);
    long size = ftell(file);
    ck_assert_msg(size > 0, "the shipped font is empty");
    rewind(file);

    font_bytes = malloc((size_t)size);
    ck_assert_ptr_nonnull(font_bytes);
    ck_assert_uint_eq(fread(font_bytes, 1, (size_t)size, file), (size_t)size);
    fclose(file);

    font_length = (size_t)size;
}

static void unload_font_file(void) {
    free(font_bytes);
    font_bytes = NULL;
    font_length = 0;
}

static rgame_typeface *open_test_typeface(void) {
    rgame_typeface *typeface = rgame_typeface_open(font_bytes, font_length, TEST_PIXEL_HEIGHT);
    ck_assert_msg(typeface != NULL, "stb refused the shipped font");
    return typeface;
}

static float advance_of(const rgame_typeface *typeface, int codepoint) {
    rgame_glyph glyph;
    ck_assert_int_eq(rgame_typeface_glyph(typeface, codepoint, &glyph), 1);
    return glyph.advance;
}

/* --- opening --- */

START_TEST(a_face_reports_the_size_it_was_opened_at) {
    rgame_typeface *typeface = open_test_typeface();

    /* Callers step by this to lay out a second line, and Gosu's Font#height
     * behaved the same way, so the port depends on it. */
    ck_assert_int_eq(rgame_typeface_height(typeface), TEST_PIXEL_HEIGHT);

    rgame_typeface_close(typeface);
}
END_TEST

START_TEST(the_baseline_sits_inside_the_line_box) {
    rgame_typeface *typeface = open_test_typeface();

    float ascent = rgame_typeface_ascent(typeface);
    ck_assert_float_gt(ascent, 0.0f);
    /* Below the top and above the bottom: descenders need the rest. */
    ck_assert_float_lt(ascent, (float)TEST_PIXEL_HEIGHT);

    rgame_typeface_close(typeface);
}
END_TEST

START_TEST(garbage_is_not_a_font) {
    unsigned char junk[256];
    memset(junk, 0xAB, sizeof(junk));

    ck_assert_ptr_null(rgame_typeface_open(junk, sizeof(junk), TEST_PIXEL_HEIGHT));
    ck_assert_ptr_null(rgame_typeface_open(NULL, 0, TEST_PIXEL_HEIGHT));
    ck_assert_ptr_null(rgame_typeface_open(font_bytes, font_length, 0));
    ck_assert_ptr_null(rgame_typeface_open(font_bytes, font_length, -4));
}
END_TEST

START_TEST(the_caller_may_free_its_buffer_immediately) {
    /* The face copies the bytes, so there is no lifetime rule to remember.
     * Under a sanitizer, a borrowed pointer here would be a use-after-free. */
    unsigned char *copy = malloc(font_length);
    memcpy(copy, font_bytes, font_length);

    rgame_typeface *typeface = rgame_typeface_open(copy, font_length, TEST_PIXEL_HEIGHT);
    ck_assert_ptr_nonnull(typeface);
    memset(copy, 0, font_length);
    free(copy);

    /* Still perfectly usable. */
    ck_assert_float_gt(advance_of(typeface, 'A'), 0.0f);

    rgame_typeface_close(typeface);
}
END_TEST

/* --- glyph metrics --- */

START_TEST(a_narrow_letter_advances_less_than_a_wide_one) {
    rgame_typeface *typeface = open_test_typeface();

    float narrow = advance_of(typeface, 'i');
    float wide = advance_of(typeface, 'W');

    ck_assert_float_gt(narrow, 0.0f);
    ck_assert_float_lt(narrow, wide);

    rgame_typeface_close(typeface);
}
END_TEST

START_TEST(advances_are_in_pixels_not_font_units) {
    /*
     * Everything else about measuring is self-consistent: a suite that only
     * compares advances to each other passes just as happily when they are all
     * still in font units, a thousand times too big, and the text draws a
     * thousand pixels apart. This pins them to the size the face was opened at.
     */
    rgame_typeface *typeface = open_test_typeface();

    for (int codepoint = ' '; codepoint < 127; codepoint++) {
        float advance = advance_of(typeface, codepoint);
        ck_assert_msg(advance > 0.0f && advance < (float)TEST_PIXEL_HEIGHT,
                      "'%c' advances %.2f, which is not a plausible pixel width at %dpx",
                      codepoint, advance, TEST_PIXEL_HEIGHT);
    }

    rgame_typeface_close(typeface);
}
END_TEST

START_TEST(a_glyph_can_sit_left_or_right_of_the_pen) {
    /* bearing_x is the gap between where the pen is and where the ink starts,
     * and it goes both ways: 'i' is inset from its pen, 'j' hangs back over the
     * letter before it. Dropping it would stack every glyph flush against the
     * pen and quietly close up the spacing. */
    rgame_typeface *typeface = open_test_typeface();

    rgame_glyph inset, overhang;
    rgame_typeface_glyph(typeface, 'i', &inset);
    rgame_typeface_glyph(typeface, 'j', &overhang);

    ck_assert_float_gt(inset.bearing_x, 0.0f);
    ck_assert_float_lt(overhang.bearing_x, 0.0f);

    rgame_typeface_close(typeface);
}
END_TEST

START_TEST(a_glyph_reports_the_size_of_its_ink) {
    rgame_typeface *typeface = open_test_typeface();

    rgame_glyph glyph;
    rgame_typeface_glyph(typeface, 'A', &glyph);

    ck_assert_int_eq(glyph.codepoint, 'A');
    ck_assert_int_gt(glyph.rect.w, 0);
    ck_assert_int_gt(glyph.rect.h, 0);
    /* A capital at 18px cannot be taller than the line box. */
    ck_assert_int_le(glyph.rect.h, TEST_PIXEL_HEIGHT + 1);
    /* Position is the atlas's business, so it comes back at the origin. */
    ck_assert_int_eq(glyph.rect.x, 0);
    ck_assert_int_eq(glyph.rect.y, 0);

    rgame_typeface_close(typeface);
}
END_TEST

START_TEST(a_space_advances_but_has_no_ink) {
    rgame_typeface *typeface = open_test_typeface();

    rgame_glyph glyph;
    rgame_typeface_glyph(typeface, ' ', &glyph);

    ck_assert_float_gt(glyph.advance, 0.0f);
    ck_assert_int_eq(glyph.rect.w, 0);
    ck_assert_int_eq(glyph.rect.h, 0);

    rgame_typeface_close(typeface);
}
END_TEST

START_TEST(a_capital_sits_below_the_top_of_the_line_box) {
    /* bearing_y is measured from the top of the line box, not the baseline —
     * the conversion this module exists to do once. A capital A starts a pixel
     * or two down; if bearing_y were still baseline-relative it would be
     * negative and every glyph would draw above the line. */
    rgame_typeface *typeface = open_test_typeface();

    rgame_glyph glyph;
    rgame_typeface_glyph(typeface, 'A', &glyph);

    ck_assert_float_ge(glyph.bearing_y, 0.0f);
    ck_assert_float_lt(glyph.bearing_y, rgame_typeface_ascent(typeface));

    rgame_typeface_close(typeface);
}
END_TEST

START_TEST(a_descender_reaches_below_the_baseline) {
    rgame_typeface *typeface = open_test_typeface();

    rgame_glyph tail;
    rgame_typeface_glyph(typeface, 'g', &tail);

    float bottom = tail.bearing_y + (float)tail.rect.h;
    ck_assert_float_gt(bottom, rgame_typeface_ascent(typeface));

    rgame_typeface_close(typeface);
}
END_TEST

START_TEST(a_codepoint_the_font_lacks_still_has_an_advance) {
    /* It resolves to .notdef, which is a visible box. A zero-width nothing
     * would swallow the character silently, and the string after it would
     * quietly close up. */
    rgame_typeface *typeface = open_test_typeface();

    rgame_glyph glyph;
    ck_assert_int_eq(rgame_typeface_glyph(typeface, 0x4E2D /* a CJK ideograph */, &glyph), 1);
    ck_assert_float_gt(glyph.advance, 0.0f);

    rgame_typeface_close(typeface);
}
END_TEST

START_TEST(the_accented_letters_the_shipped_font_promises_are_really_there) {
    /* The coverage claim behind shipping this font, checked against the bytes
     * rather than against a table someone read once. */
    rgame_typeface *typeface = open_test_typeface();

    const int codepoints[] = { 0xE4 /* a-umlaut */, 0xF6, 0xFC, 0xDF /* sharp s */,
                               0x1E9E /* capital sharp s */, 0xE9 /* e-acute */,
                               0xF1 /* n-tilde */, 0xE7 /* c-cedilla */, 0x20AC /* euro */,
                               0x201C /* curly quote */ };

    for (unsigned i = 0; i < sizeof(codepoints) / sizeof(*codepoints); i++) {
        rgame_glyph glyph;
        rgame_typeface_glyph(typeface, codepoints[i], &glyph);
        ck_assert_msg(glyph.rect.w > 0 && glyph.rect.h > 0,
                      "U+%04X rasterises to nothing in the shipped font", codepoints[i]);
    }

    rgame_typeface_close(typeface);
}
END_TEST

/* --- kerning --- */

START_TEST(kerning_pulls_an_a_and_a_v_together) {
    rgame_typeface *typeface = open_test_typeface();

    /* The textbook pair, and negative in every sane font. */
    ck_assert_float_lt(rgame_typeface_kern(typeface, 'A', 'V'), 0.0f);
    /* Nothing to kern against at the start of a string. */
    ck_assert_float_eq(rgame_typeface_kern(typeface, 0, 'A'), 0.0f);

    rgame_typeface_close(typeface);
}
END_TEST

/* --- measuring --- */

START_TEST(an_empty_string_measures_zero) {
    rgame_typeface *typeface = open_test_typeface();

    ck_assert_float_eq(rgame_typeface_measure(typeface, "", 0), 0.0f);

    rgame_typeface_close(typeface);
}
END_TEST

START_TEST(a_string_measures_the_sum_of_its_advances) {
    rgame_typeface *typeface = open_test_typeface();

    /* "lil" has no kerning pairs in it, so the width is the plain sum — which
     * makes this a check on the summing rather than on the kern table. */
    float expected = advance_of(typeface, 'l') * 2.0f + advance_of(typeface, 'i');

    ck_assert_float_eq_tol(rgame_typeface_measure(typeface, "lil", 3), expected, TOL);

    rgame_typeface_close(typeface);
}
END_TEST

START_TEST(measuring_accounts_for_kerning) {
    rgame_typeface *typeface = open_test_typeface();

    float unkerned = advance_of(typeface, 'A') + advance_of(typeface, 'V');
    float measured = rgame_typeface_measure(typeface, "AV", 2);

    ck_assert_float_lt(measured, unkerned);
    ck_assert_float_eq_tol(measured, unkerned + rgame_typeface_kern(typeface, 'A', 'V'), TOL);

    rgame_typeface_close(typeface);
}
END_TEST

START_TEST(measuring_the_same_string_twice_gives_the_same_answer) {
    /* Nothing accumulates between calls. A cursor that kept state across
     * strings would make the second label in a frame wider than the first. */
    rgame_typeface *typeface = open_test_typeface();

    float first = rgame_typeface_measure(typeface, "Score: 1200", 11);
    float second = rgame_typeface_measure(typeface, "Score: 1200", 11);

    ck_assert_float_eq(first, second);

    rgame_typeface_close(typeface);
}
END_TEST

START_TEST(a_longer_string_measures_wider) {
    rgame_typeface *typeface = open_test_typeface();

    ck_assert_float_lt(rgame_typeface_measure(typeface, "ab", 2),
                       rgame_typeface_measure(typeface, "abc", 3));
    /* Trailing whitespace counts, as it does everywhere else. */
    ck_assert_float_lt(rgame_typeface_measure(typeface, "a", 1),
                       rgame_typeface_measure(typeface, "a ", 2));

    rgame_typeface_close(typeface);
}
END_TEST

START_TEST(the_first_glyph_is_drawn_at_the_pen_not_past_it) {
    /* The position handed out is where the glyph goes, so the first one is at
     * zero. Reporting the pen *after* adding the advance shifts every string
     * right by one character and leaves the last one hanging off the end —
     * while every "the pen moves forward" and "the total is the width"
     * assertion still passes. */
    rgame_typeface *typeface = open_test_typeface();

    rgame_text_cursor cursor;
    rgame_text_cursor_init(&cursor, "Wavy", 4);

    int codepoint = 0;
    float pen_x = -1.0f;
    ck_assert_int_eq(rgame_text_cursor_next(&cursor, typeface, &codepoint, &pen_x), 1);

    ck_assert_int_eq(codepoint, 'W');
    ck_assert_float_eq(pen_x, 0.0f);
    /* And the second glyph starts exactly one advance along. */
    ck_assert_int_eq(rgame_text_cursor_next(&cursor, typeface, &codepoint, &pen_x), 1);
    ck_assert_float_eq_tol(pen_x, advance_of(typeface, 'W') +
                                      rgame_typeface_kern(typeface, 'W', 'a'), TOL);

    rgame_typeface_close(typeface);
}
END_TEST

START_TEST(measuring_and_walking_agree) {
    /*
     * The property the whole module is arranged around: the width a caller
     * measures has to be the place the last glyph actually lands. They share a
     * cursor, so this asserts the sharing rather than a coincidence.
     */
    rgame_typeface *typeface = open_test_typeface();
    const char *text = "Wavy AV. jgq";
    size_t length = strlen(text);

    rgame_text_cursor cursor;
    rgame_text_cursor_init(&cursor, text, length);

    int codepoint = 0;
    float pen_x = 0.0f;
    float previous_pen = -1.0f;
    int glyphs = 0;

    while (rgame_text_cursor_next(&cursor, typeface, &codepoint, &pen_x)) {
        /* The pen only ever moves forward, kerning included. */
        ck_assert_float_gt(pen_x, previous_pen);
        previous_pen = pen_x;
        glyphs++;
    }

    ck_assert_int_eq(glyphs, (int)length);
    ck_assert_float_eq(cursor.pen_x, rgame_typeface_measure(typeface, text, length));

    rgame_typeface_close(typeface);
}
END_TEST

/* --- rasterising --- */

START_TEST(rasterising_a_letter_produces_ink) {
    rgame_typeface *typeface = open_test_typeface();

    rgame_glyph glyph;
    rgame_typeface_glyph(typeface, 'A', &glyph);

    unsigned char bitmap[64 * 64] = { 0 };
    rgame_typeface_render(typeface, 'A', bitmap, 64, glyph.rect.w, glyph.rect.h);

    int ink = 0;
    for (int i = 0; i < 64 * 64; i++) {
        if (bitmap[i] > 0) {
            ink++;
        }
    }
    ck_assert_int_gt(ink, 0);

    rgame_typeface_close(typeface);
}
END_TEST

START_TEST(rasterising_writes_nothing_outside_the_box_it_was_given) {
    /*
     * The glyph goes into the middle of an atlas page, so it is handed a stride
     * and a sub-box of a much bigger buffer. Writing one row too far would
     * scribble over the neighbouring glyph — which looks like a packing bug and
     * is not one. The buffer is poisoned first so any stray write shows.
     */
    rgame_typeface *typeface = open_test_typeface();

    rgame_glyph glyph;
    rgame_typeface_glyph(typeface, 'W', &glyph);

    const int stride = 64;
    const int origin_x = 10, origin_y = 8;
    unsigned char page[64 * 64];
    memset(page, 0xCD, sizeof(page));

    rgame_typeface_render(typeface, 'W', &page[(origin_y * stride) + origin_x], stride,
                          glyph.rect.w, glyph.rect.h);

    for (int y = 0; y < 64; y++) {
        for (int x = 0; x < 64; x++) {
            int inside = x >= origin_x && x < origin_x + glyph.rect.w && y >= origin_y &&
                         y < origin_y + glyph.rect.h;
            if (!inside) {
                ck_assert_msg(page[(y * stride) + x] == 0xCD,
                              "wrote outside the glyph box at %d,%d", x, y);
            }
        }
    }

    rgame_typeface_close(typeface);
}
END_TEST

START_TEST(rasterising_a_space_leaves_the_buffer_alone) {
    rgame_typeface *typeface = open_test_typeface();

    unsigned char bitmap[16 * 16];
    memset(bitmap, 0xCD, sizeof(bitmap));

    rgame_glyph glyph;
    rgame_typeface_glyph(typeface, ' ', &glyph);
    /* A zero-sized box: the call has to cope, because a space is a glyph like
     * any other as far as the drawing loop is concerned. */
    rgame_typeface_render(typeface, ' ', bitmap, 16, glyph.rect.w, glyph.rect.h);

    for (unsigned i = 0; i < sizeof(bitmap); i++) {
        ck_assert_uint_eq(bitmap[i], 0xCD);
    }

    rgame_typeface_close(typeface);
}
END_TEST

/* --- UTF-8 --- */

/* Decodes a whole string and checks it against an expected codepoint list. */
static void ck_decodes_to(const char *text, const int *expected, int expected_count) {
    size_t offset = 0;
    int codepoint = 0;
    int i = 0;

    while (rgame_utf8_next(text, strlen(text), &offset, &codepoint)) {
        ck_assert_msg(i < expected_count, "decoded more codepoints than expected");
        ck_assert_int_eq(codepoint, expected[i]);
        i++;
    }

    ck_assert_int_eq(i, expected_count);
}

START_TEST(utf8_decodes_every_sequence_length) {
    /* One, two, three and four bytes: 'A', a-umlaut, euro, and an emoji. */
    const int expected[] = { 'A', 0xE4, 0x20AC, 0x1F600 };
    ck_decodes_to("A\xC3\xA4\xE2\x82\xAC\xF0\x9F\x98\x80", expected, 4);
}
END_TEST

START_TEST(utf8_handles_an_empty_string) {
    size_t offset = 0;
    int codepoint = 99;

    ck_assert_int_eq(rgame_utf8_next("", 0, &offset, &codepoint), 0);
    ck_assert_int_eq(codepoint, 99);
}
END_TEST

START_TEST(a_truncated_sequence_does_not_read_past_the_end) {
    /*
     * The one place the engine walks bytes it did not produce. A lead byte
     * promising three more at the very end of the buffer must not be believed.
     *
     * `length` is deliberately shorter than the allocation so that a decoder
     * reading past it finds real bytes rather than a page boundary — a bug that
     * ASan would otherwise only catch by luck.
     */
    const char text[] = "ab\xE2\x82\xAC";
    size_t offset = 0;
    int codepoint = 0;

    /* Pretend the buffer ends in the middle of the euro sign. */
    size_t length = 4;

    ck_assert_int_eq(rgame_utf8_next(text, length, &offset, &codepoint), 1);
    ck_assert_int_eq(codepoint, 'a');
    ck_assert_int_eq(rgame_utf8_next(text, length, &offset, &codepoint), 1);
    ck_assert_int_eq(codepoint, 'b');

    /* The truncated sequence becomes a replacement character... */
    ck_assert_int_eq(rgame_utf8_next(text, length, &offset, &codepoint), 1);
    ck_assert_int_eq(codepoint, RGAME_UTF8_REPLACEMENT);
    /* ...and the walk still terminates inside the buffer. */
    ck_assert_uint_le(offset, length);
}
END_TEST

START_TEST(malformed_bytes_cost_one_replacement_each_not_the_rest_of_the_string) {
    /* A lone continuation byte between two letters. Stopping at it would drop
     * everything after, which for a label is far worse than one visible box. */
    const int expected[] = { 'a', RGAME_UTF8_REPLACEMENT, 'b' };
    ck_decodes_to("a\x80" "b", expected, 3);
}
END_TEST

START_TEST(a_lead_byte_followed_by_the_wrong_thing_is_rejected) {
    /*
     * A two-byte lead followed by an ordinary letter. Without the continuation
     * check the letter is swallowed into the codepoint — "\xC3z" would decode
     * as one plausible-looking accented character instead of a replacement box
     * and a 'z', and the 'z' would vanish from the string.
     */
    const int expected[] = { RGAME_UTF8_REPLACEMENT, 'z' };
    ck_decodes_to("\xC3z", expected, 2);

    /* And a three-byte lead that runs into a letter part way through: the lead
     * and its one good continuation each become a replacement, and the 'z'
     * survives. */
    const int expected_mid[] = { RGAME_UTF8_REPLACEMENT, RGAME_UTF8_REPLACEMENT, 'z' };
    ck_decodes_to("\xE2\x82z", expected_mid, 3);
}
END_TEST

START_TEST(an_overlong_encoding_is_rejected) {
    /* 0xC0 0x80 is NUL written in two bytes: the classic way to sneak a
     * character past something that inspected the bytes. */
    const int expected[] = { RGAME_UTF8_REPLACEMENT, RGAME_UTF8_REPLACEMENT };
    ck_decodes_to("\xC0\x80", expected, 2);
}
END_TEST

START_TEST(a_surrogate_half_is_rejected) {
    /* U+D800 encoded as UTF-8, which is not a character. */
    const int expected[] = { RGAME_UTF8_REPLACEMENT, RGAME_UTF8_REPLACEMENT,
                             RGAME_UTF8_REPLACEMENT };
    ck_decodes_to("\xED\xA0\x80", expected, 3);
}
END_TEST

START_TEST(a_codepoint_above_the_unicode_range_is_rejected) {
    const int expected[] = { RGAME_UTF8_REPLACEMENT, RGAME_UTF8_REPLACEMENT,
                             RGAME_UTF8_REPLACEMENT, RGAME_UTF8_REPLACEMENT };
    ck_decodes_to("\xF7\xBF\xBF\xBF", expected, 4);
}
END_TEST

START_TEST(every_byte_value_is_survivable) {
    /*
     * A brute-force pass: every one-, two- and three-byte sequence, decoded
     * with the buffer length told truthfully. Nothing here asserts what the
     * *answer* is — the point is that the decoder always terminates, always
     * advances, and never steps past the length it was given. Under ASan that
     * last part is the assertion.
     */
    for (int a = 0; a < 256; a++) {
        for (int b = 0; b < 256; b += 7) {
            for (int c = 0; c < 256; c += 29) {
                char text[3] = { (char)a, (char)b, (char)c };
                size_t offset = 0;
                int codepoint = 0;
                int steps = 0;

                while (rgame_utf8_next(text, sizeof(text), &offset, &codepoint)) {
                    ck_assert_uint_le(offset, sizeof(text));
                    ck_assert_int_lt(steps, 4); /* must consume at least one byte a step */
                    steps++;
                }
                ck_assert_uint_eq(offset, sizeof(text));
            }
        }
    }
}
END_TEST

START_TEST(measuring_a_string_with_accents_walks_glyphs_not_bytes) {
    /* "Grüße" is 7 bytes and 5 glyphs. A byte-wise walk would measure it as
     * seven characters, two of them replacement boxes. */
    rgame_typeface *typeface = open_test_typeface();
    const char *text = "Gr\xC3\xBC\xC3\x9F" "e";

    rgame_text_cursor cursor;
    rgame_text_cursor_init(&cursor, text, strlen(text));

    int codepoint = 0;
    int glyphs = 0;
    while (rgame_text_cursor_next(&cursor, typeface, &codepoint, NULL)) {
        ck_assert_int_ne(codepoint, RGAME_UTF8_REPLACEMENT);
        glyphs++;
    }

    ck_assert_int_eq(glyphs, 5);
    ck_assert_float_gt(cursor.pen_x, 0.0f);

    rgame_typeface_close(typeface);
}
END_TEST

Suite *font_suite(void) {
    Suite *suite = suite_create("font");
    TCase *tc = tcase_create("core");

    /* The font file is read once for the suite rather than per test. */
    tcase_add_unchecked_fixture(tc, load_font_file, unload_font_file);

    tcase_add_test(tc, a_face_reports_the_size_it_was_opened_at);
    tcase_add_test(tc, the_baseline_sits_inside_the_line_box);
    tcase_add_test(tc, garbage_is_not_a_font);
    tcase_add_test(tc, the_caller_may_free_its_buffer_immediately);

    tcase_add_test(tc, a_narrow_letter_advances_less_than_a_wide_one);
    tcase_add_test(tc, advances_are_in_pixels_not_font_units);
    tcase_add_test(tc, a_glyph_can_sit_left_or_right_of_the_pen);
    tcase_add_test(tc, a_glyph_reports_the_size_of_its_ink);
    tcase_add_test(tc, a_space_advances_but_has_no_ink);
    tcase_add_test(tc, a_capital_sits_below_the_top_of_the_line_box);
    tcase_add_test(tc, a_descender_reaches_below_the_baseline);
    tcase_add_test(tc, a_codepoint_the_font_lacks_still_has_an_advance);
    tcase_add_test(tc, the_accented_letters_the_shipped_font_promises_are_really_there);

    tcase_add_test(tc, kerning_pulls_an_a_and_a_v_together);

    tcase_add_test(tc, an_empty_string_measures_zero);
    tcase_add_test(tc, a_string_measures_the_sum_of_its_advances);
    tcase_add_test(tc, measuring_accounts_for_kerning);
    tcase_add_test(tc, measuring_the_same_string_twice_gives_the_same_answer);
    tcase_add_test(tc, a_longer_string_measures_wider);
    tcase_add_test(tc, the_first_glyph_is_drawn_at_the_pen_not_past_it);
    tcase_add_test(tc, measuring_and_walking_agree);

    tcase_add_test(tc, rasterising_a_letter_produces_ink);
    tcase_add_test(tc, rasterising_writes_nothing_outside_the_box_it_was_given);
    tcase_add_test(tc, rasterising_a_space_leaves_the_buffer_alone);

    tcase_add_test(tc, utf8_decodes_every_sequence_length);
    tcase_add_test(tc, utf8_handles_an_empty_string);
    tcase_add_test(tc, a_truncated_sequence_does_not_read_past_the_end);
    tcase_add_test(tc, malformed_bytes_cost_one_replacement_each_not_the_rest_of_the_string);
    tcase_add_test(tc, a_lead_byte_followed_by_the_wrong_thing_is_rejected);
    tcase_add_test(tc, an_overlong_encoding_is_rejected);
    tcase_add_test(tc, a_surrogate_half_is_rejected);
    tcase_add_test(tc, a_codepoint_above_the_unicode_range_is_rejected);
    tcase_add_test(tc, every_byte_value_is_survivable);
    tcase_add_test(tc, measuring_a_string_with_accents_walks_glyphs_not_bytes);

    suite_add_tcase(suite, tc);
    return suite;
}
