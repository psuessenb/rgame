#ifndef RGAME_GLYPH_CACHE_H
#define RGAME_GLYPH_CACHE_H

#include "clip.h"

/*
 * What has already been rasterised, and where it went. Pure — no font, no
 * atlas, no GL; this module knows only that a codepoint maps to a rectangle
 * and some numbers.
 *
 * ---------------------------------------------------------------------------
 * Per glyph, never per string
 * ---------------------------------------------------------------------------
 *
 * A game draws a lot of short-lived, always-changing strings: a score, a timer,
 * a coordinate readout. Caching those *as strings* would grow one entry per
 * distinct string ever displayed, which for a timer is one per frame, forever.
 * Caching per glyph bounds the whole thing by the character set instead — a few
 * hundred entries for a Latin game, and it stops growing the moment the player
 * has seen every digit.
 *
 * That is also why there is **no eviction**. There is nothing to evict: the
 * cache cannot outgrow the glyph set the game actually draws, and dropping a
 * glyph would only mean rasterising it again next frame. A cache with no
 * eviction has no tombstones, no ages and no policy to get wrong, which is most
 * of why this file is short.
 *
 * ---------------------------------------------------------------------------
 * Open addressing
 * ---------------------------------------------------------------------------
 *
 * One flat array, probed linearly, keyed by codepoint. No node per glyph, so
 * lookup is a hash and a walk over adjacent memory — which matters because this
 * is on the per-character path of every string drawn.
 *
 * Codepoint 0 marks an empty slot. That costs nothing: 0 is NUL, which is never
 * a glyph anyone draws, and inserting it is refused rather than quietly
 * corrupting the table.
 */

/* One cached glyph: where its pixels are, and how to place them. */
typedef struct {
    int codepoint;
    int page; /* which atlas page holds it */
    /* Where on that page, in pixels. Empty for a glyph with no ink, such as a
     * space — which is still cached, because its advance is worth keeping. */
    rgame_rect rect;

    /* How far the pen moves after drawing it, in pixels at the font's size. */
    float advance;
    /* Where the pixels sit relative to the pen: x from the pen position, y from
     * the *top of the line box* rather than the baseline, because that is the
     * corner a caller passes to `text`. Converting once, here, keeps the
     * baseline out of every drawing calculation downstream. */
    float bearing_x, bearing_y;
} rgame_glyph;

typedef struct {
    rgame_glyph *entries; /* NULL until the first insert */
    unsigned int capacity; /* always a power of two, or 0 */
    unsigned int count;
} rgame_glyph_cache;

/* An empty cache that has allocated nothing. A font that never draws text
 * therefore costs nothing beyond this struct. */
void rgame_glyph_cache_init(rgame_glyph_cache *cache);

/* Frees the table. Safe on an empty cache, and safe to call twice. */
void rgame_glyph_cache_destroy(rgame_glyph_cache *cache);

/* Writes the cached glyph and returns 1, or returns 0 and leaves `out`
 * untouched. */
int rgame_glyph_cache_find(const rgame_glyph_cache *cache, int codepoint, rgame_glyph *out);

/*
 * Stores a glyph, replacing any entry for the same codepoint. Returns 1 on
 * success and 0 if the codepoint is 0 or the table could not grow.
 *
 * A failed insert is not fatal to the caller: the glyph simply is not cached,
 * and gets rasterised again next time. Slow, but correct — which is the right
 * failure mode for a cache.
 */
int rgame_glyph_cache_insert(rgame_glyph_cache *cache, const rgame_glyph *glyph);

/* How many distinct codepoints are cached. Bounded by the character set the
 * game draws, which is the property the whole design rests on. */
unsigned int rgame_glyph_cache_count(const rgame_glyph_cache *cache);

#endif /* RGAME_GLYPH_CACHE_H */
