/*
 * atlas.c — the shelf packer. See atlas.h for the shape of it and why shelves
 * are enough.
 */

#include "atlas.h"

void rgame_atlas_init(rgame_atlas *atlas, int width, int height) {
    atlas->width = width > 0 ? width : 0;
    atlas->height = height > 0 ? height : 0;
    atlas->shelf_y = 0;
    atlas->shelf_height = 0;
    atlas->cursor_x = 0;
}

int rgame_atlas_place(rgame_atlas *atlas, int width, int height, rgame_rect *out) {
    if (!atlas || !out) {
        return 0;
    }

    /* Nothing to pack. Succeeds with an empty rectangle: see atlas.h. */
    if (width <= 0 || height <= 0) {
        *out = rgame_rect_make(atlas->cursor_x, atlas->shelf_y, 0, 0);
        return 1;
    }

    /* No amount of shelving will make it fit, so say so now rather than after
     * opening an empty shelf for it. */
    if (width > atlas->width || height > atlas->height) {
        return 0;
    }

    /* Out of room on this shelf? Drop to a new one below the *tallest* glyph
     * on the old one — not below the last one placed, which may be short and
     * would let the new shelf overlap a taller neighbour. */
    if (atlas->cursor_x + width > atlas->width) {
        atlas->shelf_y += atlas->shelf_height + RGAME_ATLAS_GUTTER;
        atlas->shelf_height = 0;
        atlas->cursor_x = 0;
    }

    if (atlas->shelf_y + height > atlas->height) {
        /* The page is full. Nothing has been changed that a caller could
         * observe except the shelf move above, which only ever makes the page
         * emptier-looking; the next place() will fail the same way. */
        return 0;
    }

    *out = rgame_rect_make(atlas->cursor_x, atlas->shelf_y, width, height);

    /* The gutter goes after the glyph, so the next one on this shelf starts a
     * pixel clear of it, and the next shelf starts a pixel below this one. */
    atlas->cursor_x += width + RGAME_ATLAS_GUTTER;
    if (height > atlas->shelf_height) {
        atlas->shelf_height = height;
    }

    return 1;
}
