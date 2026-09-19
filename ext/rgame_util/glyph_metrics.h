#ifndef RGAME_GLYPH_METRICS_H
#define RGAME_GLYPH_METRICS_H

/*
 * What a typeface says about one glyph: how big its bitmap is and how it sits
 * against the pen. Facts about the face, and nothing about where the glyph ends
 * up — placing it on an atlas page is the atlas's business, and that half lives
 * in `rgame_glyph` (glyph_cache.h), which holds one of these.
 *
 * Kept apart so the typeface layer depends on nothing but this header. A
 * glyph's size was once written as a rectangle whose `x` and `y` were always
 * zero, and that one rectangle tied the pure face to the graphics layer.
 */
typedef struct {
    int codepoint;
    /* The bitmap it rasterises to, in pixels. Zero for a glyph with no ink,
     * such as a space. */
    int width, height;

    /* How far the pen moves after drawing it, in pixels at the font's size. */
    float advance;
    /* Where the pixels sit relative to the pen: x from the pen position, y from
     * the *top of the line box* rather than the baseline, because that is the
     * corner a caller passes to `text`. Converting once, here, keeps the
     * baseline out of every drawing calculation downstream. */
    float bearing_x, bearing_y;
} rgame_glyph_metrics;

#endif /* RGAME_GLYPH_METRICS_H */
