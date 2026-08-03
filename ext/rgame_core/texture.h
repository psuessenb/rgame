#ifndef RGAME_TEXTURE_H
#define RGAME_TEXTURE_H

#include "clip.h"

/*
 * Textures: what part of an uploaded image a draw call should sample, and who
 * owns the upload. Pure arithmetic and pure bookkeeping — no GL, no stb, no
 * I/O. The decode-and-upload half lives in image.c, which is deliberately as
 * dumb as it can be (CLAUDE.md's layer 3).
 *
 * ---------------------------------------------------------------------------
 * Two structs, because there are two lifetimes
 * ---------------------------------------------------------------------------
 *
 * A sprite sheet is decoded and uploaded to the GPU *once*, and then sliced
 * into dozens of sprites. Each of those sprites is an ordinary object a game
 * holds, drops and garbage-collects on its own schedule — but the pixels
 * behind them are one shared allocation on the GPU.
 *
 * So:
 *
 *   rgame_texture_sheet   one GL texture. Reference-counted, heap-allocated,
 *                         shared by every view into it.
 *   rgame_texture         a *view*: a sheet plus the sub-rectangle of it this
 *                         particular sprite occupies. Small, copyable, holds
 *                         one reference to its sheet.
 *
 * `subimage` therefore costs a rectangle intersection and a refcount bump —
 * no second decode and no second upload. Slicing a 512x512 sheet into 1024
 * tiles produces 1024 views over one texture.
 *
 * ---------------------------------------------------------------------------
 * Why the refcount is here and not in image.c
 * ---------------------------------------------------------------------------
 *
 * "Free the GPU texture exactly when the last sprite using it goes away" is
 * the kind of rule that is wrong in one branch and leaks for a year. It is
 * also, written out, pure integer bookkeeping — nothing about it needs a GPU.
 * So it lives here, where `test/test_texture.c` can drop views in every order
 * and assert the sheet dies once and only once.
 *
 * The one thing this module cannot do is call `glDeleteTextures`. Instead
 * `rgame_texture_sheet_release` *reports* that the last reference went away
 * and hands back the GL name it was holding; the caller in image.c does the
 * one-line deletion. That keeps the decision here and the syscall there.
 *
 * ---------------------------------------------------------------------------
 * Pixels in, UVs out
 * ---------------------------------------------------------------------------
 *
 * Callers talk in pixels — "the tile at 32,16, sixteen by sixteen" — because
 * that is how sprite sheets are drawn and described. OpenGL samples in
 * normalised texture coordinates, 0..1 across the whole texture. Converting
 * between them is one division that is easy to get subtly wrong (by the sheet
 * size, not the view size), so it happens in exactly one place:
 * `rgame_texture_uv`.
 */

typedef struct {
    /* The GL texture name. Opaque here: this module never calls GL, it only
     * carries the number so that release can hand it back for deletion. */
    unsigned int name;
    int width, height; /* the whole uploaded image, in pixels */
    int refs;
} rgame_texture_sheet;

typedef struct {
    rgame_texture_sheet *sheet;
    /* The part of the sheet this view samples, in sheet pixels. */
    rgame_rect rect;
} rgame_texture;

/*
 * Creates a sheet with one reference, or NULL if out of memory or given a
 * degenerate size. `name` is whatever the GL layer allocated; this module
 * treats it as an opaque token, so tests can pass any number they like.
 */
rgame_texture_sheet *rgame_texture_sheet_create(unsigned int name, int width, int height);

void rgame_texture_sheet_retain(rgame_texture_sheet *sheet);

/*
 * Drops one reference. Returns 1 if that was the last one — in which case the
 * sheet has been freed and `*out_name` holds the GL name the caller must now
 * delete — and 0 if others remain (`*out_name` untouched).
 *
 * Returning the name rather than deleting it is what keeps this file free of
 * GL. `out_name` may not be NULL when the caller intends to honour the
 * deletion; passing NULL is allowed and simply discards it, which is what the
 * tests that only care about lifetimes do.
 */
int rgame_texture_sheet_release(rgame_texture_sheet *sheet, unsigned int *out_name);

/*
 * A view covering the whole sheet, retaining it. Every view — this one
 * included — must eventually be passed to rgame_texture_destroy.
 */
rgame_texture rgame_texture_whole(rgame_texture_sheet *sheet);

/* Drops this view's reference. Same return contract as sheet_release, so a
 * caller can delete the GL texture when the last view goes. */
int rgame_texture_destroy(rgame_texture *view, unsigned int *out_name);

/* An independent view of the same region — retains the sheet. */
rgame_texture rgame_texture_clone(const rgame_texture *view);

/*
 * A sub-rectangle of `view`, in coordinates *relative to that view* — so
 * slicing a slice composes without the caller tracking absolute offsets.
 *
 * Returns 1 on success. Returns 0, leaving `*out` untouched, if the rect is
 * degenerate or reaches outside the view: garbage UVs sample a neighbouring
 * sprite, which looks like a drawing bug rather than the indexing bug it is,
 * so this refuses instead of clamping.
 */
int rgame_texture_subimage(const rgame_texture *view, int x, int y, int w, int h,
                           rgame_texture *out);

int rgame_texture_width(const rgame_texture *view);
int rgame_texture_height(const rgame_texture *view);

/*
 * How many whole `tile_width` x `tile_height` tiles fit, row-major. A partial
 * tile at the right or bottom edge is not counted — a sheet whose size is not
 * a multiple of the tile size has a strip of padding, and half a sprite is
 * never what was meant. Zero or negative tile sizes yield 0.
 */
int rgame_texture_tile_count(const rgame_texture *view, int tile_width, int tile_height);

/* The `index`-th tile, counting left to right then top to bottom. Returns 1 on
 * success, 0 if the index is outside the count above. */
int rgame_texture_tile(const rgame_texture *view, int tile_width, int tile_height, int index,
                       rgame_texture *out);

/*
 * The view's four corners in normalised texture coordinates, written to `uv8`
 * as x,y pairs in the same corner order the canvas takes a quad's points:
 * top-left, top-right, bottom-right, bottom-left.
 *
 * v runs downwards, matching the pixel rect and the screen: image row 0 is
 * v = 0. That holds because image.c uploads the decoded rows in the order stb
 * produces them (top row first), rather than flipping them the way a
 * bottom-left-origin convention would need.
 */
void rgame_texture_uv(const rgame_texture *view, float *uv8);

/*
 * How many sheets are alive right now — for tests, not for gameplay.
 *
 * A leaked GPU texture is invisible: the game runs, the frame rate is fine,
 * and video memory fills up over an hour of play. This counter makes "the
 * texture went away when the last sprite using it did" an assertion, both in
 * the Check suite and from Ruby, where the collector chooses the order in
 * which an app and its images are swept.
 *
 * Single-threaded, like the rest of the engine.
 */
long rgame_texture_live_sheets(void);

#endif /* RGAME_TEXTURE_H */
