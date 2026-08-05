#ifndef RGAME_ATLAS_H
#define RGAME_ATLAS_H

#include "graphics/clip.h"

/*
 * Where the next glyph goes on a texture page. Pure arithmetic — no GL, no
 * font, no idea what a glyph even is.
 *
 * Uploading one small texture per character would be hopeless: a string of
 * twenty characters would be twenty texture binds and twenty draw calls. So
 * every glyph of a font is packed into one big page and drawn from a
 * sub-rectangle of it, exactly like sprites out of a sprite sheet — which means
 * a whole string is one batch.
 *
 * ---------------------------------------------------------------------------
 * Shelves, and why that is enough
 * ---------------------------------------------------------------------------
 *
 * Rectangle packing in general is a hard problem with a literature attached.
 * This is not the general problem: glyphs arrive one at a time, in whatever
 * order the game happens to draw them, and they are nearly all the same height
 * because they came from one font at one size. For that, shelves are the right
 * amount of cleverness — fill a row left to right, start a new row underneath
 * when it runs out, and give up when the page does:
 *
 *      +-----------------------------+
 *      | A | B | C | D |             |   <- a full shelf, shelf_height = tallest
 *      +---+---+---+---+-------------+
 *      | E | F |^cursor_x            |   <- the shelf being filled
 *      +-------+                     |
 *      |                             |
 *      +-----------------------------+
 *
 * The waste is the ragged right edge of each shelf plus the gap under short
 * glyphs, which for one font at one size is a few percent. A smarter packer
 * would buy back that few percent in exchange for being much harder to be sure
 * about, and pages are cheap: when one fills, the caller opens another.
 *
 * ---------------------------------------------------------------------------
 * The gutter is this module's job
 * ---------------------------------------------------------------------------
 *
 * Glyph atlases are sampled with linear filtering, so a texel at the edge of one
 * glyph blends with whatever is next to it. Packed flush, that is the
 * neighbouring letter, and every glyph draws with a sliver of the next one down
 * its side.
 *
 * The fix is a one-pixel gap, and it is reserved *inside* `rgame_atlas_place`
 * rather than added by each caller. A caller that has to remember is a caller
 * that eventually does not, and the result looks like a rendering bug rather
 * than the packing bug it is.
 */

/* Kept between glyphs so linear sampling cannot blend two of them together. */
#define RGAME_ATLAS_GUTTER 1

typedef struct {
    int width, height;

    int shelf_y;      /* top edge of the row currently being filled */
    int shelf_height; /* the tallest glyph placed on that row so far */
    int cursor_x;     /* next free x on that row */
} rgame_atlas;

/* An empty page of the given size. A degenerate size yields a page that refuses
 * everything, rather than one that hands out rectangles outside itself. */
void rgame_atlas_init(rgame_atlas *atlas, int width, int height);

/*
 * Reserves room for a `width` x `height` glyph and writes where it went.
 *
 * Returns 1 when it fit and 0 when the page is full — that 0 is the caller's
 * signal to start another page, not an error. `out` is left untouched on
 * failure, so a caller that ignores the return value gets a stale rectangle
 * rather than a garbage one.
 *
 * A glyph with no pixels (the space character rasterises to nothing) succeeds
 * and reserves nothing: the answer is an empty rectangle, which uploads nothing
 * and samples nothing. That is the honest result rather than a special case the
 * caller has to know about.
 */
int rgame_atlas_place(rgame_atlas *atlas, int width, int height, rgame_rect *out);

#endif /* RGAME_ATLAS_H */
