/*
 * font.c — metrics and rasterisation over stb_truetype. See font.h.
 */

#include "font.h"

#include <stdlib.h>
#include <string.h>

#include "vendor/stb_truetype.h"

struct rgame_typeface {
    stbtt_fontinfo info;
    /* Our own copy: stb keeps pointers into this for the life of the face, and
     * a borrowed buffer would be a lifetime rule callers have to remember. */
    unsigned char *ttf;

    int pixel_height;
    float scale;  /* font units -> pixels at that height */
    float ascent; /* pixels from the top of the line box to the baseline */
};

rgame_typeface *rgame_typeface_open(const unsigned char *ttf, size_t length, int pixel_height) {
    if (!ttf || length == 0 || pixel_height <= 0) {
        return NULL;
    }

    rgame_typeface *typeface = calloc(1, sizeof(rgame_typeface));
    if (!typeface) {
        return NULL;
    }

    typeface->ttf = malloc(length);
    if (!typeface->ttf) {
        free(typeface);
        return NULL;
    }
    memcpy(typeface->ttf, ttf, length);

    /* Index 0 of a font collection. A .ttc with several faces in it is a thing
     * that exists; picking anything but the first would need a way to say
     * which, and nothing has asked for one. */
    int offset = stbtt_GetFontOffsetForIndex(typeface->ttf, 0);
    if (offset < 0 || !stbtt_InitFont(&typeface->info, typeface->ttf, offset)) {
        free(typeface->ttf);
        free(typeface);
        return NULL;
    }

    typeface->pixel_height = pixel_height;
    typeface->scale = stbtt_ScaleForPixelHeight(&typeface->info, (float)pixel_height);

    int ascent = 0, descent = 0, line_gap = 0;
    stbtt_GetFontVMetrics(&typeface->info, &ascent, &descent, &line_gap);
    typeface->ascent = (float)ascent * typeface->scale;

    return typeface;
}

void rgame_typeface_close(rgame_typeface *typeface) {
    if (!typeface) {
        return;
    }
    free(typeface->ttf);
    free(typeface);
}

int rgame_typeface_height(const rgame_typeface *typeface) {
    return typeface ? typeface->pixel_height : 0;
}

float rgame_typeface_ascent(const rgame_typeface *typeface) {
    return typeface ? typeface->ascent : 0.0f;
}

int rgame_typeface_glyph(const rgame_typeface *typeface, int codepoint, rgame_glyph *out) {
    if (!typeface || !out) {
        return 0;
    }

    int advance = 0, left_bearing = 0;
    stbtt_GetCodepointHMetrics(&typeface->info, codepoint, &advance, &left_bearing);

    /* The ink's bounding box relative to the *baseline*, so y0 is negative for
     * anything reaching above it — which is nearly everything. */
    int x0 = 0, y0 = 0, x1 = 0, y1 = 0;
    stbtt_GetCodepointBitmapBox(&typeface->info, codepoint, typeface->scale, typeface->scale,
                                &x0, &y0, &x1, &y1);

    out->codepoint = codepoint;
    out->page = 0;
    /* Size only. Where it lands on a page is the atlas's decision. */
    out->rect = rgame_rect_make(0, 0, x1 - x0, y1 - y0);
    out->advance = (float)advance * typeface->scale;
    out->bearing_x = (float)x0;
    /* Baseline-relative to top-of-line-box, converted once and never again. */
    out->bearing_y = typeface->ascent + (float)y0;

    return 1;
}

void rgame_typeface_render(const rgame_typeface *typeface, int codepoint, unsigned char *out,
                           int stride, int width, int height) {
    /* stb copes with a zero-sized box on its own, so mutating this guard away
     * survives the suite. It stays for the *negative* case, which stb does not
     * promise anything about, and a negative size here would come from an
     * atlas rectangle that had already gone wrong. */
    if (!typeface || !out || width <= 0 || height <= 0) {
        return;
    }

    stbtt_MakeCodepointBitmap(&typeface->info, out, width, height, stride, typeface->scale,
                              typeface->scale, codepoint);
}

float rgame_typeface_kern(const rgame_typeface *typeface, int previous, int codepoint) {
    /*
     * No previous glyph means nothing to kern against — the first letter of a
     * string is where it is.
     *
     * Removing this guard survives the suite, because the shipped font has no
     * kern pair involving codepoint 0 and so answers zero anyway. It stays
     * because that is a fact about one font, not about kerning: a font with
     * such a pair would shift the first letter of every string it drew.
     */
    if (!typeface || previous == 0) {
        return 0.0f;
    }

    int kern = stbtt_GetCodepointKernAdvance(&typeface->info, previous, codepoint);
    return (float)kern * typeface->scale;
}

/* ------------------------------------------------------------------------- *
 * UTF-8
 * ------------------------------------------------------------------------- */

/* A continuation byte is 10xxxxxx and nothing else. */
static int is_continuation(unsigned char byte) {
    return (byte & 0xC0) == 0x80;
}

/*
 * One malformed byte costs one replacement character, not the rest of the
 * string: `*offset` always moves by at least one, so a caller looping on this
 * always terminates however bad the input is.
 */
static int reject(size_t *offset, int *codepoint) {
    *offset += 1;
    *codepoint = RGAME_UTF8_REPLACEMENT;
    return 1;
}

int rgame_utf8_next(const char *text, size_t length, size_t *offset, int *codepoint) {
    if (!text || !offset || !codepoint || *offset >= length) {
        return 0;
    }

    const unsigned char *bytes = (const unsigned char *)text;
    unsigned char lead = bytes[*offset];

    if (lead < 0x80) {
        *codepoint = lead;
        *offset += 1;
        return 1;
    }

    /* How many bytes the lead announces, and the value its low bits carry. A
     * lead of 10xxxxxx is a continuation with nothing in front of it, and
     * 11111xxx is not a lead byte at all — both land in the else. */
    int extra;
    int value;
    if ((lead & 0xE0) == 0xC0) {
        extra = 1;
        value = lead & 0x1F;
    } else if ((lead & 0xF0) == 0xE0) {
        extra = 2;
        /* 0x0F, not 0x1F: a three-byte lead is 1110xxxx, so the fifth bit is
         * always clear and the two masks happen to be equivalent here. Written
         * as the four bits the format actually defines — a mutation to 0x1F is
         * undetectable, and that is a property of the lead range rather than a
         * gap in the tests. */
        value = lead & 0x0F;
    } else if ((lead & 0xF8) == 0xF0) {
        extra = 3;
        value = lead & 0x07;
    } else {
        return reject(offset, codepoint);
    }

    /* Truncated: the sequence runs off the end of the buffer. Checked before
     * reading any of it, which is the whole point. */
    if (*offset + (size_t)extra >= length) {
        return reject(offset, codepoint);
    }

    for (int i = 1; i <= extra; i++) {
        unsigned char byte = bytes[*offset + (size_t)i];
        if (!is_continuation(byte)) {
            return reject(offset, codepoint);
        }
        value = (value << 6) | (byte & 0x3F);
    }

    /*
     * Overlong encodings — a codepoint written in more bytes than it needs —
     * are rejected rather than accepted. They are the classic way to smuggle a
     * character past a check that looked at the bytes, and they have no
     * legitimate use.
     */
    static const int minimum[4] = { 0, 0x80, 0x800, 0x10000 };
    if (value < minimum[extra]) {
        return reject(offset, codepoint);
    }
    /* Surrogate halves are not characters, and nothing above U+10FFFF exists. */
    if ((value >= 0xD800 && value <= 0xDFFF) || value > 0x10FFFF) {
        return reject(offset, codepoint);
    }

    *offset += (size_t)(extra + 1);
    *codepoint = value;
    return 1;
}

/* ------------------------------------------------------------------------- *
 * Walking a string
 * ------------------------------------------------------------------------- */

void rgame_text_cursor_init(rgame_text_cursor *cursor, const char *text, size_t length) {
    cursor->text = text;
    cursor->length = text ? length : 0;
    cursor->offset = 0;
    cursor->previous = 0;
    cursor->pen_x = 0.0f;
}

int rgame_text_cursor_next(rgame_text_cursor *cursor, const rgame_typeface *typeface,
                           int *codepoint, float *pen_x) {
    if (!cursor || !typeface || !codepoint) {
        return 0;
    }

    int next = 0;
    if (!rgame_utf8_next(cursor->text, cursor->length, &cursor->offset, &next)) {
        return 0;
    }

    /* Kerning belongs to the gap *before* this glyph, so it moves the pen
     * before the position is handed out. */
    cursor->pen_x += rgame_typeface_kern(typeface, cursor->previous, next);

    *codepoint = next;
    if (pen_x) {
        *pen_x = cursor->pen_x;
    }

    rgame_glyph glyph;
    rgame_typeface_glyph(typeface, next, &glyph);
    cursor->pen_x += glyph.advance;
    cursor->previous = next;

    return 1;
}

float rgame_typeface_measure(const rgame_typeface *typeface, const char *text, size_t length) {
    if (!typeface || !text) {
        return 0.0f;
    }

    /* The same walk drawing uses, run to the end and asked where it got to.
     * Not "the same arithmetic" — the same code. */
    rgame_text_cursor cursor;
    rgame_text_cursor_init(&cursor, text, length);

    int codepoint = 0;
    while (rgame_text_cursor_next(&cursor, typeface, &codepoint, NULL)) {
        /* nothing to do; the cursor is doing the summing */
    }

    return cursor.pen_x;
}
