#ifndef RGAME_FONT_INTERNAL_H
#define RGAME_FONT_INTERNAL_H

#include "font.h"
#include "rgame/core.h"

/*
 * What the drawing path needs from inside an `rgame_font`.
 *
 * `rgame_font` is opaque in the public header and stays that way — a caller
 * outside this extension has no business knowing what an atlas page is. But
 * app.c has to walk a string and place its glyphs, so the accessors live here,
 * in a header that is not under include/ and therefore cannot leave
 * ext/rgame_core/. Same arrangement as image_internal.h.
 */

/* The face behind the font, for measuring and walking a string. */
const rgame_typeface *rgame_font_typeface(const rgame_font *font);

/* The app whose GL context the atlas pages live in, or NULL. Compared against
 * the app being drawn into, for the same reason images are — a texture from
 * another context samples nothing and paints white. */
rgame_app *rgame_font_owner(const rgame_font *font);

/*
 * A glyph ready to draw: cached if it has been seen, and otherwise rasterised,
 * packed onto a page and uploaded on the spot.
 *
 * Also reports which GL texture to bind and how big it is, since the caller
 * needs both to turn the glyph's page rectangle into texture coordinates.
 *
 * Returns 1 on success, 0 if the glyph could not be made — out of memory, or an
 * atlas page that refused a glyph bigger than a whole page. A caller should
 * skip that glyph and carry on drawing the rest of the string.
 *
 * Uploading mid-frame is fine: uploads happen immediately while drawing is
 * deferred, so the page is complete long before the frame is submitted.
 */
int rgame_font_glyph(rgame_font *font, int codepoint, rgame_glyph *out, unsigned int *texture,
                     int *page_width, int *page_height);

/* How many atlas pages exist across all live fonts — for tests, the way
 * rgame_texture_live_sheets is for images. A leaked page is invisible
 * otherwise. */
long rgame_font_live_pages(void);

#endif /* RGAME_FONT_INTERNAL_H */
