/*
 * font_atlas.c — the one file in the text stack that touches GL.
 *
 * Everything interesting about text is elsewhere and pure: font.c knows what
 * glyphs measure and look like, atlas.c knows where the next one goes on a
 * page, glyph_cache.c knows which have been done already. This composes the
 * three, owns the GL textures behind the pages, and reads the font file. That
 * is layer 3 in CLAUDE.md's abstraction strategy, and it is kept this thin
 * precisely so "we don't unit-test it directly" is honest rather than a gap —
 * `spec_core/rgame/core/font_spec.rb` and the renderer's pixel checks exercise
 * it end to end against a real GL context.
 *
 * ---------------------------------------------------------------------------
 * Why the pages are GL_ALPHA
 * ---------------------------------------------------------------------------
 *
 * A rasterised glyph is coverage: one byte per pixel saying how much ink is
 * there. Uploading that as RGBA would cost four times the memory to say the
 * same thing three redundant ways.
 *
 * An alpha texture under the fixed-function default (GL_MODULATE) gives
 * `rgb = the vertex colour, a = vertex alpha * coverage`, which is exactly what
 * coloured text is. No shader, no second code path in the backend — the glyph
 * quads go through the same textured-quad call sprites do.
 *
 * Worth knowing for the day the project moves to core-profile GL: GL_ALPHA does
 * not exist there. The equivalent is GL_RED plus a swizzle in a shader.
 */

#include "rgame/core.h"

#include "app_gl.h"
#include "atlas.h"
#include "font.h"
#include "font_internal.h"
#include "glyph_cache.h"

#include <SDL2/SDL_opengl.h>
#include <stdio.h>
#include <stdlib.h>

/*
 * Big enough that a Latin character set fits on one page — a few hundred glyphs
 * at the sizes a game uses — and small enough that a font nobody draws much
 * with has not cost a megabyte. 256 KB per page, one byte per pixel.
 *
 * A page that fills is not a problem: another one opens, and the only cost is
 * that a string spanning both takes two draw calls instead of one.
 */
#define RGAME_FONT_PAGE_SIZE 512

typedef struct {
    unsigned int texture; /* GL name */
    rgame_atlas atlas;
} rgame_font_page;

struct rgame_font {
    rgame_app *app; /* retained, like an image's — see image.c */
    rgame_typeface *typeface;
    rgame_glyph_cache cache;

    rgame_font_page *pages;
    int page_count, page_capacity;

    /* Reused for every rasterisation rather than malloc'd per glyph. Grown to
     * the largest glyph seen and never shrunk; a font's biggest glyph is small
     * and is met within the first few words. */
    unsigned char *scratch;
    size_t scratch_size;
};

/* See rgame_font_live_pages. Single-threaded, like the rest of the engine. */
static long live_pages = 0;

long rgame_font_live_pages(void) {
    return live_pages;
}

/* ------------------------------------------------------------------------- *
 * Pages
 * ------------------------------------------------------------------------- */

/*
 * Allocates a blank page on the GPU. The caller must already have made the
 * font's GL context current.
 *
 * The page is uploaded zeroed rather than left undefined: the gutters between
 * glyphs are sampled by linear filtering at every glyph's edge, and undefined
 * memory there is a fringe of noise around every letter.
 */
static int add_page(rgame_font *font) {
    if (font->page_count == font->page_capacity) {
        int capacity = font->page_capacity ? font->page_capacity * 2 : 2;
        rgame_font_page *pages = realloc(font->pages, sizeof(rgame_font_page) * (size_t)capacity);
        if (!pages) {
            return 0;
        }
        font->pages = pages;
        font->page_capacity = capacity;
    }

    unsigned char *blank = calloc(RGAME_FONT_PAGE_SIZE * RGAME_FONT_PAGE_SIZE, 1);
    if (!blank) {
        return 0;
    }

    unsigned int texture = 0;
    glGenTextures(1, &texture);
    if (texture == 0) {
        free(blank);
        return 0;
    }

    glBindTexture(GL_TEXTURE_2D, texture);
    /* One byte per pixel and an arbitrary glyph width, so GL's default
     * four-byte row alignment would shear every upload. */
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    /* Linear, unlike sprites: text is not pixel art, and stb hands us
     * antialiased coverage that nearest sampling would throw away. */
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_ALPHA, RGAME_FONT_PAGE_SIZE, RGAME_FONT_PAGE_SIZE, 0,
                 GL_ALPHA, GL_UNSIGNED_BYTE, blank);
    glBindTexture(GL_TEXTURE_2D, 0);

    free(blank);

    rgame_font_page *page = &font->pages[font->page_count++];
    page->texture = texture;
    rgame_atlas_init(&page->atlas, RGAME_FONT_PAGE_SIZE, RGAME_FONT_PAGE_SIZE);
    live_pages++;
    return 1;
}

/* ------------------------------------------------------------------------- *
 * Loading
 * ------------------------------------------------------------------------- */

static void set_error(char *err, size_t err_size, const char *format, const char *detail) {
    if (err && err_size > 0) {
        snprintf(err, err_size, format, detail);
    }
}

/* Same shape as image.c's reader: the engine decides how a missing file is
 * reported, not the library that parses what is in it. */
static unsigned char *read_whole_file(const char *path, long *out_size) {
    FILE *file = fopen(path, "rb");
    if (!file) {
        return NULL;
    }

    if (fseek(file, 0, SEEK_END) != 0) {
        fclose(file);
        return NULL;
    }
    long size = ftell(file);
    if (size <= 0) {
        fclose(file);
        return NULL;
    }
    rewind(file);

    unsigned char *bytes = malloc((size_t)size);
    if (!bytes) {
        fclose(file);
        return NULL;
    }

    size_t got = fread(bytes, 1, (size_t)size, file);
    fclose(file);
    if (got != (size_t)size) {
        free(bytes);
        return NULL;
    }

    *out_size = size;
    return bytes;
}

rgame_font *rgame_font_load(rgame_app *app, const char *path, int pixel_height, char *err,
                            size_t err_size) {
    if (!app || !path) {
        set_error(err, err_size, "%s", "no app or path given");
        return NULL;
    }
    if (pixel_height <= 0) {
        set_error(err, err_size, "%s", "a font size must be positive");
        return NULL;
    }

    long size = 0;
    unsigned char *bytes = read_whole_file(path, &size);
    if (!bytes) {
        set_error(err, err_size, "could not read %s", path);
        return NULL;
    }

    rgame_font *font = calloc(1, sizeof(rgame_font));
    if (!font) {
        free(bytes);
        set_error(err, err_size, "%s", "out of memory");
        return NULL;
    }

    /* The face copies what it needs, so the file buffer goes straight back. */
    font->typeface = rgame_typeface_open(bytes, (size_t)size, pixel_height);
    free(bytes);
    if (!font->typeface) {
        free(font);
        set_error(err, err_size, "could not read %s as a TrueType font", path);
        return NULL;
    }

    rgame_glyph_cache_init(&font->cache);
    rgame_app_gl_retain(app);
    font->app = app;

    /* No page yet. A font that is only ever measured — a layout pass that never
     * draws — costs no video memory at all. */
    return font;
}

void rgame_font_destroy(rgame_font *font) {
    if (!font) {
        return;
    }

    if (font->page_count > 0) {
        /* Deleting a texture acts on whatever context is current, so say which
         * and put back what was there — a collector picks this moment, quite
         * possibly in the middle of another window's frame. If the app is
         * already gone the pages went with its context, and there is nothing
         * to delete. */
        rgame_gl_context_save saved;
        if (rgame_app_gl_make_current(font->app, &saved)) {
            for (int i = 0; i < font->page_count; i++) {
                glDeleteTextures(1, &font->pages[i].texture);
            }
        }
        rgame_app_gl_restore(&saved);
        live_pages -= font->page_count;
    }

    free(font->pages);
    free(font->scratch);
    rgame_glyph_cache_destroy(&font->cache);
    rgame_typeface_close(font->typeface);
    rgame_app_gl_release(font->app);
    free(font);
}

/* ------------------------------------------------------------------------- *
 * Queries
 * ------------------------------------------------------------------------- */

int rgame_font_height(const rgame_font *font) {
    return font ? rgame_typeface_height(font->typeface) : 0;
}

float rgame_font_measure(const rgame_font *font, const char *text, size_t length) {
    /* Measuring touches no GL and needs no page, so it works outside a frame —
     * which matters, because laying out a menu happens in update, not draw. */
    return font ? rgame_typeface_measure(font->typeface, text, length) : 0.0f;
}

const rgame_typeface *rgame_font_typeface(const rgame_font *font) {
    return font ? font->typeface : NULL;
}

rgame_app *rgame_font_owner(const rgame_font *font) {
    return font ? font->app : NULL;
}

/* ------------------------------------------------------------------------- *
 * Rasterising on demand
 * ------------------------------------------------------------------------- */

/* Packs a glyph onto a page with room for it, opening a new one if the last is
 * full. Returns the page index, or -1. */
static int place_on_a_page(rgame_font *font, int width, int height, rgame_rect *out) {
    if (font->page_count > 0 &&
        rgame_atlas_place(&font->pages[font->page_count - 1].atlas, width, height, out)) {
        return font->page_count - 1;
    }

    if (!add_page(font)) {
        return -1;
    }
    if (!rgame_atlas_place(&font->pages[font->page_count - 1].atlas, width, height, out)) {
        /* Bigger than a whole page. Nothing to be done for it, and a fresh page
         * would refuse it too — so give up on this glyph rather than opening a
         * page per attempt for the rest of the run. */
        return -1;
    }
    return font->page_count - 1;
}

static int ensure_scratch(rgame_font *font, size_t needed) {
    if (font->scratch_size >= needed) {
        return 1;
    }

    unsigned char *scratch = realloc(font->scratch, needed);
    if (!scratch) {
        return 0;
    }
    font->scratch = scratch;
    font->scratch_size = needed;
    return 1;
}

int rgame_font_glyph(rgame_font *font, int codepoint, rgame_glyph *out, unsigned int *texture,
                     int *page_width, int *page_height) {
    if (!font || !out) {
        return 0;
    }

    if (page_width) {
        *page_width = RGAME_FONT_PAGE_SIZE;
    }
    if (page_height) {
        *page_height = RGAME_FONT_PAGE_SIZE;
    }

    if (rgame_glyph_cache_find(&font->cache, codepoint, out)) {
        if (texture) {
            *texture = font->pages[out->page].texture;
        }
        return 1;
    }

    rgame_glyph glyph;
    if (!rgame_typeface_glyph(font->typeface, codepoint, &glyph)) {
        return 0;
    }

    /*
     * A glyph with no ink — a space — is cached with an empty rectangle and
     * never touches a page or the GPU. Its advance is the whole reason it is
     * cached at all.
     */
    if (glyph.rect.w > 0 && glyph.rect.h > 0) {
        rgame_gl_context_save saved;
        if (!rgame_app_gl_make_current(font->app, &saved)) {
            rgame_app_gl_restore(&saved);
            return 0;
        }

        rgame_rect placed;
        int page = place_on_a_page(font, glyph.rect.w, glyph.rect.h, &placed);
        size_t pixels = (size_t)glyph.rect.w * (size_t)glyph.rect.h;

        if (page < 0 || !ensure_scratch(font, pixels)) {
            rgame_app_gl_restore(&saved);
            return 0;
        }

        rgame_typeface_render(font->typeface, codepoint, font->scratch, glyph.rect.w,
                              glyph.rect.w, glyph.rect.h);

        glBindTexture(GL_TEXTURE_2D, font->pages[page].texture);
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
        glTexSubImage2D(GL_TEXTURE_2D, 0, placed.x, placed.y, placed.w, placed.h, GL_ALPHA,
                        GL_UNSIGNED_BYTE, font->scratch);
        glBindTexture(GL_TEXTURE_2D, 0);

        rgame_app_gl_restore(&saved);

        glyph.page = page;
        glyph.rect = placed;
    }

    /* A cache that could not grow is not fatal: the glyph is drawn from what
     * was just rasterised and simply gets rasterised again next time. */
    rgame_glyph_cache_insert(&font->cache, &glyph);

    *out = glyph;
    if (texture) {
        *texture = glyph.rect.w > 0 ? font->pages[glyph.page].texture : 0;
    }
    return 1;
}
