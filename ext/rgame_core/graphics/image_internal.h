#ifndef RGAME_IMAGE_INTERNAL_H
#define RGAME_IMAGE_INTERNAL_H

#include "rgame/core.h"
#include "graphics/texture.h"

/*
 * The texture view inside an image handle.
 *
 * `rgame_image` is opaque in the public header, and stays that way: a caller
 * outside this extension has no business knowing what a texture view is. But
 * the drawing path does — app.c has to hand the view to primitives.c — so the
 * accessor lives here, in a header that is not under include/ and therefore
 * cannot leave ext/rgame_core/.
 *
 * Returns NULL for a NULL image. The view belongs to the image; it must not be
 * destroyed by the caller.
 */
const rgame_texture *rgame_image_view(const rgame_image *image);

/*
 * The app whose GL context this image was uploaded into, or NULL.
 *
 * Textures are not shared between contexts, so drawing an image through a
 * *different* app samples nothing and paints a plain white quad — no GL error,
 * no clue. The draw path compares owners so that this can be reported instead.
 */
rgame_app *rgame_image_owner(const rgame_image *image);

#endif /* RGAME_IMAGE_INTERNAL_H */
