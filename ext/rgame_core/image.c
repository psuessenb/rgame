/*
 * image.c — decode a PNG, upload it to the GPU, hand back a handle.
 *
 * This is "layer 3" in CLAUDE.md's abstraction strategy: the thin shim where
 * real calls happen. Everything interesting about images — which rectangle of
 * a sheet a sprite covers, how that becomes texture coordinates, when the
 * shared upload may be deleted — is in texture.{c,h}, is pure, and is covered
 * by test/test_texture.c with no GPU in sight. What is left here is a file
 * read, one stb call and four GL calls, and it is kept this thin precisely so
 * that "we don't unit-test it directly" is an honest position rather than a
 * gap. `spec_core/rgame/core/image_spec.rb` exercises it end to end against a
 * real GL context under Xvfb.
 *
 * ---------------------------------------------------------------------------
 * What a handle is
 * ---------------------------------------------------------------------------
 *
 * `struct rgame_image` is one `rgame_texture` view on the heap, plus the app it
 * was uploaded into. The heap part exists only so the public API can be an
 * opaque pointer; the view itself is a small value. Subimages and tiles
 * allocate another one of these pointing at the same sheet, which is why
 * slicing is cheap.
 *
 * The app pointer is carried because deleting a GL texture, like creating one,
 * acts on whatever context is current — so freeing an image has to say which
 * context it means. Each handle *retains* the app struct (not the window) for
 * as long as it lives, which is what makes that pointer safe to follow even
 * when the app was destroyed first. In that case the context is already gone,
 * `rgame_app_gl_make_current` says so, and the deletion is skipped — correctly,
 * because destroying a GL context frees every texture in it.
 *
 * That ordering is not hypothetical: Ruby can collect an app and its images in
 * the same pass, and nothing specifies which is swept first.
 */

#include "rgame/core.h"

#include "app_gl.h"
#include "texture.h"
#include "vendor/stb_image.h"

#include <SDL2/SDL_opengl.h>
#include <stdio.h>
#include <stdlib.h>

struct rgame_image {
    rgame_app *app; /* borrowed — the app owns the context these pixels live in */
    rgame_texture view;
};

/* Writes a message into the caller's buffer, if they asked for one. Every
 * failure path below goes through this so none of them can forget. */
static void set_error(char *err, size_t err_size, const char *format, const char *detail) {
    if (err && err_size > 0) {
        snprintf(err, err_size, format, detail);
    }
}

/*
 * Reads a whole file into a malloc'd buffer.
 *
 * stb is built with STBI_NO_STDIO (see stb_image_impl.c) so that reading the
 * file is our decision rather than the decoder's: one place decides how a
 * missing file is reported, and the same code path will serve data that never
 * was a file — an archive entry, or an asset baked into the gem.
 */
static unsigned char *read_whole_file(const char *path, long *out_size) {
    FILE *file = fopen(path, "rb");
    if (!file) {
        return NULL;
    }

    /* Seek to the end and ask where we are: the portable way to get a file's
     * size without a stat() that differs per platform. */
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

    /* A short read means a truncated or vanishing file; treat it as a failure
     * rather than handing the decoder a partly-filled buffer. */
    size_t got = fread(bytes, 1, (size_t)size, file);
    fclose(file);
    if (got != (size_t)size) {
        free(bytes);
        return NULL;
    }

    *out_size = size;
    return bytes;
}

/*
 * Uploads RGBA8 pixels and returns the GL texture name, or 0 on failure.
 *
 * `pixels` is tightly packed, top row first — which is the order stb decodes
 * in, and the order texture.c's UVs assume (v increases downwards). Uploading
 * bottom-up instead is the classic way every sprite ends up mirrored.
 */
static unsigned int upload_rgba(const unsigned char *pixels, int width, int height) {
    unsigned int name = 0;
    glGenTextures(1, &name);
    if (name == 0) {
        return 0;
    }

    glBindTexture(GL_TEXTURE_2D, name);

    /* Rows are 4 bytes per pixel so they are already 4-byte aligned, but GL's
     * default alignment of 4 is a trap waiting for the day something uploads
     * 3-byte or 1-byte pixels; saying 1 makes the upload independent of it. */
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);

    /* Nearest-neighbour, always: this engine draws pixel art, and there is no
     * case where blurring it on scale-up is what was wanted. */
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);

    /* Clamp rather than repeat. Sprites come from a shared sheet, so a UV that
     * slips a hair past an edge should pick up that edge's own pixel — with
     * GL_REPEAT it wraps to the far side of the *sheet* and paints a stripe of
     * an unrelated sprite. */
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, pixels);
    glBindTexture(GL_TEXTURE_2D, 0);

    return name;
}

/* Wraps a view in a handle, releasing the view again if the allocation fails —
 * so a failed subimage does not strand a reference on the sheet forever. */
static rgame_image *wrap(rgame_app *app, rgame_texture view) {
    rgame_image *image = malloc(sizeof(rgame_image));
    if (!image) {
        unsigned int orphan = 0;
        if (rgame_texture_destroy(&view, &orphan)) {
            rgame_gl_context_save saved;
            if (rgame_app_gl_make_current(app, &saved)) {
                glDeleteTextures(1, &orphan);
            }
            rgame_app_gl_restore(&saved);
        }
        return NULL;
    }

    rgame_app_gl_retain(app);
    image->app = app;
    image->view = view;
    return image;
}

rgame_image *rgame_image_load(rgame_app *app, const char *path, char *err, size_t err_size) {
    if (!app || !path) {
        set_error(err, err_size, "%s", "no app or path given");
        return NULL;
    }

    /* Loading is allowed mid-frame, and a game with two windows may well be
     * mid-frame in the *other* one, so whatever was current goes back at every
     * exit below. */
    rgame_gl_context_save saved;
    if (!rgame_app_gl_make_current(app, &saved)) {
        rgame_app_gl_restore(&saved);
        set_error(err, err_size, "%s", "could not make the app's GL context current");
        return NULL;
    }

    long size = 0;
    unsigned char *bytes = read_whole_file(path, &size);
    if (!bytes) {
        rgame_app_gl_restore(&saved);
        set_error(err, err_size, "could not read %s", path);
        return NULL;
    }

    /* The trailing 4 asks stb for four channels whatever the file has, so a
     * greyscale or palette PNG arrives as RGBA too and the upload below has
     * exactly one format to handle. */
    int width = 0, height = 0, channels_in_file = 0;
    unsigned char *pixels = stbi_load_from_memory(bytes, (int)size, &width, &height,
                                                  &channels_in_file, 4);
    free(bytes);
    if (!pixels) {
        rgame_app_gl_restore(&saved);
        set_error(err, err_size, "could not decode %s", path);
        return NULL;
    }

    unsigned int name = upload_rgba(pixels, width, height);
    stbi_image_free(pixels);
    if (name == 0) {
        rgame_app_gl_restore(&saved);
        set_error(err, err_size, "%s", "GL refused to allocate a texture");
        return NULL;
    }

    rgame_texture_sheet *sheet = rgame_texture_sheet_create(name, width, height);
    if (!sheet) {
        glDeleteTextures(1, &name);
        rgame_app_gl_restore(&saved);
        set_error(err, err_size, "%s", "out of memory");
        return NULL;
    }

    /* The sheet is created with one reference and the view takes a second, so
     * hand back the creation reference: from here the handles own it. */
    rgame_texture view = rgame_texture_whole(sheet);
    rgame_texture_sheet_release(sheet, NULL);

    rgame_image *image = wrap(app, view);
    rgame_app_gl_restore(&saved);
    if (!image) {
        set_error(err, err_size, "%s", "out of memory");
    }
    return image;
}

rgame_image *rgame_image_subimage(const rgame_image *image, int x, int y, int width, int height) {
    if (!image) {
        return NULL;
    }

    rgame_texture view = {0};
    if (!rgame_texture_subimage(&image->view, x, y, width, height, &view)) {
        return NULL;
    }

    return wrap(image->app, view);
}

int rgame_image_tile_count(const rgame_image *image, int tile_width, int tile_height) {
    return image ? rgame_texture_tile_count(&image->view, tile_width, tile_height) : 0;
}

rgame_image *rgame_image_tile(const rgame_image *image, int tile_width, int tile_height,
                              int index) {
    if (!image) {
        return NULL;
    }

    rgame_texture view = {0};
    if (!rgame_texture_tile(&image->view, tile_width, tile_height, index, &view)) {
        return NULL;
    }

    return wrap(image->app, view);
}

int rgame_image_width(const rgame_image *image) {
    return image ? rgame_texture_width(&image->view) : 0;
}

int rgame_image_height(const rgame_image *image) {
    return image ? rgame_texture_height(&image->view) : 0;
}

const rgame_texture *rgame_image_view(const rgame_image *image) {
    return image ? &image->view : NULL;
}

rgame_app *rgame_image_owner(const rgame_image *image) {
    return image ? image->app : NULL;
}

void rgame_image_destroy(rgame_image *image) {
    if (!image) {
        return;
    }

    /* Only the *last* handle on a sheet gets a name back to delete, which is
     * how dropping a sprite sheet while its tiles are still alive stays safe.
     *
     * make_current fails when the app was destroyed first, and skipping the
     * deletion is then the right answer rather than a leak: tearing down a GL
     * context takes its textures with it. */
    unsigned int name = 0;
    if (rgame_texture_destroy(&image->view, &name)) {
        rgame_gl_context_save saved;
        if (rgame_app_gl_make_current(image->app, &saved)) {
            glDeleteTextures(1, &name);
        }
        /* Always restored, including when the switch failed: a collector runs
         * this at an arbitrary moment, quite possibly in the middle of another
         * window's frame, and that frame still has to be submitted into its own
         * context. */
        rgame_app_gl_restore(&saved);
    }
    rgame_app_gl_release(image->app);
    free(image);
}
