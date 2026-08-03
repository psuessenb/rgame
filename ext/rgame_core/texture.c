/*
 * texture.c — sheet refcounting, sub-rectangle composition, pixel-to-UV.
 * See texture.h for what the two structs are and why the refcount lives here.
 */

#include "texture.h"

#include <stdlib.h>

/* See rgame_texture_live_sheets in the header for why this exists. */
static long live_sheets = 0;

long rgame_texture_live_sheets(void) {
    return live_sheets;
}

rgame_texture_sheet *rgame_texture_sheet_create(unsigned int name, int width, int height) {
    if (width <= 0 || height <= 0) {
        return NULL;
    }

    rgame_texture_sheet *sheet = malloc(sizeof(rgame_texture_sheet));
    if (!sheet) {
        return NULL;
    }

    sheet->name = name;
    sheet->width = width;
    sheet->height = height;
    sheet->refs = 1;
    live_sheets++;
    return sheet;
}

void rgame_texture_sheet_retain(rgame_texture_sheet *sheet) {
    if (sheet) {
        sheet->refs++;
    }
}

int rgame_texture_sheet_release(rgame_texture_sheet *sheet, unsigned int *out_name) {
    if (!sheet) {
        return 0;
    }

    if (--sheet->refs > 0) {
        return 0;
    }

    /* Read the name out before freeing — after free(sheet) it is gone, and
     * reading it back is the classic use-after-free this ordering avoids. */
    unsigned int name = sheet->name;
    free(sheet);
    live_sheets--;
    if (out_name) {
        *out_name = name;
    }
    return 1;
}

rgame_texture rgame_texture_whole(rgame_texture_sheet *sheet) {
    rgame_texture view = {0};
    if (!sheet) {
        return view;
    }

    rgame_texture_sheet_retain(sheet);
    view.sheet = sheet;
    view.rect = rgame_rect_make(0, 0, sheet->width, sheet->height);
    return view;
}

int rgame_texture_destroy(rgame_texture *view, unsigned int *out_name) {
    if (!view || !view->sheet) {
        return 0;
    }

    int died = rgame_texture_sheet_release(view->sheet, out_name);
    /* Clearing the pointer makes a second destroy a no-op rather than a double
     * free. Ruby's GC and an explicit close can both reach the same view. */
    view->sheet = NULL;
    view->rect = rgame_rect_make(0, 0, 0, 0);
    return died;
}

rgame_texture rgame_texture_clone(const rgame_texture *view) {
    rgame_texture copy = {0};
    if (!view || !view->sheet) {
        return copy;
    }

    rgame_texture_sheet_retain(view->sheet);
    copy = *view;
    return copy;
}

int rgame_texture_subimage(const rgame_texture *view, int x, int y, int w, int h,
                           rgame_texture *out) {
    if (!view || !view->sheet || !out || w <= 0 || h <= 0 || x < 0 || y < 0) {
        return 0;
    }

    /* Compared against the *view's* size, not the sheet's: a sub-rect is
     * relative to what it is being cut from, so a tile of a tile can never
     * wander outside the tile it came from. */
    if (x + w > view->rect.w || y + h > view->rect.h) {
        return 0;
    }

    rgame_texture_sheet_retain(view->sheet);
    out->sheet = view->sheet;
    out->rect = rgame_rect_make(view->rect.x + x, view->rect.y + y, w, h);
    return 1;
}

int rgame_texture_width(const rgame_texture *view) {
    return view && view->sheet ? view->rect.w : 0;
}

int rgame_texture_height(const rgame_texture *view) {
    return view && view->sheet ? view->rect.h : 0;
}

int rgame_texture_tile_count(const rgame_texture *view, int tile_width, int tile_height) {
    if (!view || !view->sheet || tile_width <= 0 || tile_height <= 0) {
        return 0;
    }

    return (view->rect.w / tile_width) * (view->rect.h / tile_height);
}

int rgame_texture_tile(const rgame_texture *view, int tile_width, int tile_height, int index,
                       rgame_texture *out) {
    /* `index < 0` is redundant today and deliberately kept: a negative index
     * yields negative offsets, which rgame_texture_subimage refuses anyway, so
     * mutating it away survives the suite. Half a range check is still the
     * wrong thing to read at the place the range is computed. */
    if (index < 0 || index >= rgame_texture_tile_count(view, tile_width, tile_height)) {
        return 0;
    }

    int columns = view->rect.w / tile_width;
    return rgame_texture_subimage(view, (index % columns) * tile_width,
                                  (index / columns) * tile_height, tile_width, tile_height, out);
}

void rgame_texture_uv(const rgame_texture *view, float *uv8) {
    if (!uv8) {
        return;
    }

    /* A view with no sheet has no pixels to sample; hand back a degenerate
     * 0,0 square rather than dividing by a zero sheet size. */
    if (!view || !view->sheet) {
        for (int i = 0; i < 8; i++) {
            uv8[i] = 0.0f;
        }
        return;
    }

    /* Normalise against the *sheet*: UVs address the whole uploaded texture,
     * so a 16px tile in a 512px sheet spans 1/32 of the coordinate space, not
     * all of it. Dividing by the view size instead is the mistake this
     * function exists to make impossible to repeat. */
    float sheet_w = (float)view->sheet->width;
    float sheet_h = (float)view->sheet->height;

    float u0 = (float)view->rect.x / sheet_w;
    float v0 = (float)view->rect.y / sheet_h;
    float u1 = (float)(view->rect.x + view->rect.w) / sheet_w;
    float v1 = (float)(view->rect.y + view->rect.h) / sheet_h;

    uv8[0] = u0; uv8[1] = v0; /* top-left */
    uv8[2] = u1; uv8[3] = v0; /* top-right */
    uv8[4] = u1; uv8[5] = v1; /* bottom-right */
    uv8[6] = u0; uv8[7] = v1; /* bottom-left */
}
