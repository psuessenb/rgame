/*
 * stb_truetype_impl.c — the one translation unit that instantiates stb_truetype.
 *
 * Same shape as stb_image_impl.c next door, and for the same reason: a
 * single-header library emits its function bodies only in the file that defines
 * STB_TRUETYPE_IMPLEMENTATION, so exactly one file does, and it contains
 * nothing else. That lets font.c include the header the ordinary way without
 * producing a second copy of every symbol at link time, and lets the build
 * relax -Wall -Wextra for the vendored code and nothing else.
 *
 * Unlike stb_image, no feature macros are set here. The defaults are what the
 * glyph atlas wants: the v2 rasteriser (antialiased coverage, which is what
 * gets uploaded as the alpha channel of an atlas page) and ordinary malloc for
 * the temporary buffers it allocates while filling a shape.
 *
 * Deliberately *not* STBTT_STATIC: font.c is a different translation unit and
 * has to be able to call these.
 *
 * Licence: stb_truetype is public domain / MIT. See vendor/README.md.
 */

#define STB_TRUETYPE_IMPLEMENTATION
#include "vendor/stb_truetype.h"
