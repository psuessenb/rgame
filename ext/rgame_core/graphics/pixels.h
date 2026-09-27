#ifndef RGAME_PIXELS_H
#define RGAME_PIXELS_H

#include <stddef.h>

/*
 * pixels.h — arithmetic on RGBA8 bytes. Pure: bytes in, bytes out.
 *
 * Every colour the engine hands GL is premultiplied: its red, green and blue
 * are already multiplied by its own alpha. An image is premultiplied once,
 * when it loads, and a vertex colour when the canvas writes it. The GL backend
 * then blends with GL_ONE as the source factor.
 *
 * Filtering is why. A filter averages neighbouring texels, and a straight
 * colour weighs a transparent texel's RGB as fully as an opaque one's. A PNG's
 * transparent pixels are usually black, so every smoothed edge would darken.
 * A premultiplied transparent texel is 0, 0, 0, 0, and adds nothing.
 */

/* Multiplies each pixel's colour by its own alpha, in place. `rgba` is RGBA8,
 * tightly packed, as stb decodes it. A fully transparent pixel becomes
 * 0, 0, 0, 0, whatever colour it stored. */
void rgame_pixels_premultiply(unsigned char *rgba, size_t pixel_count);

/*
 * One byte scaled by another, `value * by / 255` rounded to the nearest byte.
 * Scaling by 255 returns `value` unchanged, which is what keeps an opaque
 * colour exactly the bytes it was.
 *
 * `static inline` because the canvas calls it three times for every vertex it
 * writes. The trick below is exact for every pair of bytes, which
 * test/test_pixels.c checks for all 65,536.
 */
static inline unsigned char rgame_pixels_scale(unsigned char value, unsigned char by) {
    unsigned int product = ((unsigned int)value * by) + 128u;
    return (unsigned char)((product + (product >> 8)) >> 8);
}

#endif /* RGAME_PIXELS_H */
