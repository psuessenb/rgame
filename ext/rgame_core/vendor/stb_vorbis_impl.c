/*
 * stb_vorbis_impl.c — the one translation unit that instantiates stb_vorbis.
 *
 * The odd one out among the vendored implementation files: stb_vorbis ships as
 * a `.c` rather than a `.h`. The split still works the same way, because it
 * honours `STB_VORBIS_HEADER_ONLY` — this file includes it *without* that macro
 * to emit the code, and vorbis_decoder.c includes it *with* the macro to get
 * only the declarations. Without that split both translation units would define
 * every symbol and the link would fail.
 *
 * Decoding only. stb_vorbis has a pushdata API for streaming from a callback,
 * which the engine does not use — see vorbis_decoder.c for why it buffers the
 * compressed file instead.
 *
 * Licence: stb_vorbis is public domain / MIT. See vendor/README.md.
 */

/*
 * No integer-decode path: the decoder hands miniaudio 32-bit floats, which is
 * what its data sources speak. It guards only the integer-output functions,
 * none of which vorbis_decoder.c calls, so the declarations it sees without
 * this macro still match what is compiled here.
 */
#define STB_VORBIS_NO_INTEGER_CONVERSION

/* stdio stays in: opening by filename is one of the decoder's two entry
 * points. */

#include "vendor/stb_vorbis.c"
