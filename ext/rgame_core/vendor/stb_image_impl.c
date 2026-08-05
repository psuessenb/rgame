/*
 * stb_image_impl.c — the one translation unit that instantiates stb_image.
 *
 * `stb_image.h` is a "single-header library": including it normally gives you
 * the declarations, and including it *once* with STB_IMAGE_IMPLEMENTATION
 * defined also emits the function bodies. That one place is this file, and it
 * contains nothing else — so image.c can include the header the ordinary way
 * without producing a second copy of every symbol at link time.
 *
 * Having it alone in its own file is also what lets the build relax
 * -Wall -Wextra for it specifically (see extconf.rb and the root Makefile).
 * The project stays warning-clean; the carve-out is exactly one file wide and
 * visible here rather than hidden in a global flag.
 *
 * Licence: stb_image is public domain / MIT. See vendor/README.md.
 */

/* PNG is the only format the engine loads, and every format compiled in is
 * both dead code and another parser reachable from a game's asset files. */
#define STBI_ONLY_PNG

/* No stdio path: images are read through rgame's own file loading in image.c,
 * which means one place decides how a missing file is reported. */
#define STBI_NO_STDIO

/* The engine uploads 8-bit RGBA to GL and has no use for HDR or 16-bit paths. */
#define STBI_NO_LINEAR
#define STBI_NO_HDR

#define STB_IMAGE_IMPLEMENTATION
#include "vendor/stb_image.h"
