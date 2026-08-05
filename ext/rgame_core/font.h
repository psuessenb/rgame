#ifndef RGAME_FONT_H
#define RGAME_FONT_H

#include <stddef.h>

#include "glyph_cache.h"

/*
 * A typeface at one pixel size: what each glyph measures, and what it looks
 * like. Wraps `stb_truetype` and nothing else — no atlas, no cache, no GL, no
 * file I/O.
 *
 * This is the layer that can be tested exactly, and it is testable *because*
 * the engine ships its own font: `test/test_font.c` opens
 * `lib/rgame/fonts/LiberationSans-Regular.ttf` and asserts on real advances and
 * real ink. Nothing here needs a fixture, a mock, or a display.
 *
 * "Typeface" rather than "font" because the public `rgame_font` (core.h) is the
 * composed thing — this plus an atlas, a glyph cache and GL textures. This is
 * only the part that knows what letters are shaped like.
 *
 * ---------------------------------------------------------------------------
 * One walk, used by measuring and by drawing
 * ---------------------------------------------------------------------------
 *
 * `rgame_text_cursor` below is not a convenience. Measuring a string and
 * drawing it must agree to the last fraction of a pixel, or every centred
 * label in the game sits slightly off and nothing points at why. Two loops that
 * both "sum the advances" drift the moment one of them gains a rounding rule or
 * forgets kerning — so there is one loop, and both callers turn its crank.
 *
 * ---------------------------------------------------------------------------
 * Coordinates
 * ---------------------------------------------------------------------------
 *
 * Everything is in pixels at the typeface's size, and vertical measurements are
 * from the **top of the line box** rather than the baseline. Typography works
 * from the baseline; a caller placing a label works from a corner. Converting
 * once, here, keeps the baseline out of every drawing calculation downstream.
 */

typedef struct rgame_typeface rgame_typeface;

/*
 * Opens a TrueType font at `pixel_height`, or NULL if the data is not a font
 * this can read, or the size is not positive.
 *
 * **The bytes are copied**, so the caller may free its buffer immediately.
 * stb keeps pointers into the font data for the life of the face, and a
 * borrowed buffer would make that a lifetime rule someone has to remember; a
 * few hundred kilobytes per open font is the cheaper answer.
 */
rgame_typeface *rgame_typeface_open(const unsigned char *ttf, size_t length, int pixel_height);
void rgame_typeface_close(rgame_typeface *typeface);

/*
 * The size the face was opened at, which is also the line height a caller
 * should step by for a second line. stb scales a font so that ascent minus
 * descent is exactly the requested pixel height, so this is the em box, not an
 * approximation of it.
 */
int rgame_typeface_height(const rgame_typeface *typeface);

/* Distance from the top of the line box down to the baseline. */
float rgame_typeface_ascent(const rgame_typeface *typeface);

/*
 * Metrics for one glyph: its advance, its bearings, and the *size* of the
 * bitmap it would rasterise to, written into `out->rect` as `w` and `h` with
 * `x` and `y` left at zero — where on a page it goes is the atlas's decision,
 * not this module's.
 *
 * Returns 1 always for a face that is open; a codepoint the font has no glyph
 * for still yields the `.notdef` box, which is deliberately something visible
 * rather than a zero-width nothing that swallows characters silently.
 */
int rgame_typeface_glyph(const rgame_typeface *typeface, int codepoint, rgame_glyph *out);

/*
 * Rasterises a glyph into a caller-provided 8-bit coverage buffer — 0 is
 * transparent, 255 is solid ink. `stride` is the distance between rows, so a
 * glyph can be written straight into the middle of a bigger buffer.
 *
 * Writes nothing outside the `width` x `height` box it is given.
 */
void rgame_typeface_render(const rgame_typeface *typeface, int codepoint, unsigned char *out,
                           int stride, int width, int height);

/*
 * The kerning adjustment between two adjacent glyphs, in pixels — usually zero,
 * usually negative when not. Without it "AV" reads as two letters that happen
 * to be near each other.
 */
float rgame_typeface_kern(const rgame_typeface *typeface, int previous, int codepoint);

/* ------------------------------------------------------------------------- *
 * Walking a string
 * ------------------------------------------------------------------------- */

typedef struct {
    const char *text;
    size_t length;
    size_t offset;
    int previous;  /* the glyph before, for kerning; 0 at the start */
    float pen_x;   /* how far along the line the pen has travelled */
} rgame_text_cursor;

void rgame_text_cursor_init(rgame_text_cursor *cursor, const char *text, size_t length);

/*
 * Steps to the next glyph. Returns 1 and writes the codepoint plus the pen
 * position it should be drawn at; returns 0 at the end of the string.
 *
 * Kerning against the previous glyph is applied *before* the position is
 * reported, and the advance afterwards — so `cursor->pen_x` once this returns 0
 * is the width of the whole string.
 */
int rgame_text_cursor_next(rgame_text_cursor *cursor, const rgame_typeface *typeface,
                           int *codepoint, float *pen_x);

/* The width of a UTF-8 string in pixels: the cursor above, run to the end. */
float rgame_typeface_measure(const rgame_typeface *typeface, const char *text, size_t length);

/*
 * Decodes one UTF-8 codepoint starting at `*offset` and advances it. Returns 1
 * on success and 0 at the end of the string.
 *
 * Malformed input yields U+FFFD and advances exactly one byte, rather than
 * stopping: a string can come from a data file, and one bad byte should cost
 * one visible replacement character, not the rest of the label. Never reads
 * past `length` — this is the only place in the engine that walks bytes it did
 * not produce.
 */
int rgame_utf8_next(const char *text, size_t length, size_t *offset, int *codepoint);

/* What a malformed byte decodes to: U+FFFD REPLACEMENT CHARACTER. */
#define RGAME_UTF8_REPLACEMENT 0xFFFD

#endif /* RGAME_FONT_H */
