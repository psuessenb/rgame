#ifndef RGAME_VORBIS_DECODER_H
#define RGAME_VORBIS_DECODER_H

#include "vendor/miniaudio.h"

/*
 * Ogg Vorbis for miniaudio, over vendored stb_vorbis.
 *
 * miniaudio cannot read Ogg Vorbis. It decodes wav, mp3 and flac, and vorbis is
 * expected to arrive as a *custom decoding backend* — a small vtable the caller
 * registers. miniaudio ships a reference one, but it uses **system libvorbis**,
 * which would hand back the very dependency the engine avoided by vendoring
 * miniaudio in the first place (see
 * docs/plans/gosu-replacement/README.md). So this is that backend, over
 * stb_vorbis, which is already here and needs nothing installed.
 *
 * ---------------------------------------------------------------------------
 * Why there are two ways in
 * ---------------------------------------------------------------------------
 *
 * A decoding backend can offer `onInitFile`, which is handed a path, and
 * `onInit`, which is handed read/seek/tell callbacks. Both are needed, and
 * finding that out is unpleasant: `ma_decoder_init_file` uses the first, but
 * `ma_engine` — where voices, streaming and mixing live — reads everything
 * through its own virtual file system and calls the second. A backend with only
 * `onInitFile` loads perfectly through `ma_decoder` and then fails inside the
 * engine with a bare `MA_INVALID_FILE` and no indication why.
 *
 * stb_vorbis has no callback-based open: it offers filename, memory, and a
 * pushdata API. So the callback path reads the whole *compressed* file into
 * memory and opens that. For a music track that is a few megabytes — against
 * roughly forty for a full PCM decode of the same three minutes — and the
 * pushdata API, which would avoid even that, is a great deal more machinery
 * than the difference is worth.
 */

/*
 * The backend to hand miniaudio, via `ma_decoder_config.ppCustomBackendVTables`
 * or `ma_resource_manager_config.ppCustomDecodingBackendVTables`. Registering
 * it is what makes every `.ogg` path in the engine work.
 */
extern ma_decoding_backend_vtable rgame_vorbis_decoding_backend;

#endif /* RGAME_VORBIS_DECODER_H */
