/*
 * pixels.c — premultiplying decoded pixels. See pixels.h for why the engine
 * premultiplies at all.
 */

#include "graphics/pixels.h"

void rgame_pixels_premultiply(unsigned char *rgba, size_t pixel_count) {
    for (size_t i = 0; i < pixel_count; i++) {
        unsigned char *pixel = rgba + (i * 4);
        unsigned char alpha = pixel[3];
        if (alpha == 255) {
            continue;
        }
        pixel[0] = rgame_pixels_scale(pixel[0], alpha);
        pixel[1] = rgame_pixels_scale(pixel[1], alpha);
        pixel[2] = rgame_pixels_scale(pixel[2], alpha);
    }
}
