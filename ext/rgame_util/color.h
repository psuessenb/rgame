#ifndef RGAME_COLOR_H
#define RGAME_COLOR_H

#include <stdint.h>

/*
 * RGBA colour packing — pure arithmetic, no Ruby, no SDL, no GL.
 *
 * A colour is a *value*: four bytes, no handle, nothing to release. That is why
 * it lives in the graphics-free half of the project even though the renderer is
 * its main consumer — the engine layer may hold Util values as attributes but
 * may not name RGame::Core at all, so a colour in Core would be out of reach of
 * the scene nodes that want to store one. See CLAUDE.md, "Value objects go in
 * Util; only handle-owners go in Core".
 *
 * The packed form is 0xRRGGBBAA, which is how a human writes a colour and how
 * `Color#packed` reads back.
 */

typedef uint32_t rgame_color;

/* Components outside 0..255 are clamped, so this is total: there is no way to
 * call it wrong. The Ruby wrapper is stricter and raises instead, because a
 * Ruby caller passing 300 has a bug worth hearing about. */
rgame_color rgame_color_rgba(int r, int g, int b, int a);

int rgame_color_r(rgame_color color);
int rgame_color_g(rgame_color color);
int rgame_color_b(rgame_color color);
int rgame_color_a(rgame_color color);

/*
 * Writes the four components into `out` in R, G, B, A order — the order
 * OpenGL reads them with glColorPointer(4, GL_UNSIGNED_BYTE, ...).
 *
 * Use this rather than copying the packed uint32 into a vertex. The two are not
 * interchangeable: on a little-endian machine the bytes of 0xRRGGBBAA come out
 * A, B, G, R, so GL would read the alpha as red. Going through bytes sidesteps
 * the question entirely and is endian-independent.
 */
void rgame_color_bytes(rgame_color color, unsigned char out[4]);

#define RGAME_COLOR_WHITE ((rgame_color)0xFFFFFFFFu)
#define RGAME_COLOR_BLACK ((rgame_color)0x000000FFu)
#define RGAME_COLOR_TRANSPARENT ((rgame_color)0x00000000u)

#endif /* RGAME_COLOR_H */
