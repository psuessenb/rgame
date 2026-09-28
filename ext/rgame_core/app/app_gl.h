#ifndef RGAME_APP_GL_H
#define RGAME_APP_GL_H

#include "app/teardown_queue.h"
#include "rgame/core.h"

/*
 * The one thing other engine files need from inside `struct rgame_app`: its GL
 * context. Private to the implementation — this header is not under include/,
 * so nothing outside ext/rgame_core/ can reach it, and the public API stays a
 * single opaque handle.
 */

/*
 * Whatever was current before a switch, so it can be put back. Opaque handles;
 * the header still names no SDL types.
 */
typedef struct {
    void *window;
    void *context;
} rgame_gl_context_save;

/*
 * Makes this app's GL context current on the calling thread. Returns 1 on
 * success, 0 if SDL refused — which includes the case of an app whose window
 * has already been destroyed, so this doubles as "is there still a context
 * here?".
 *
 * GL has no notion of "which window" per call — every call acts on whatever
 * context is current. With one window that is already the right one, but
 * uploading a texture while a *second* window's context happened to be current
 * would put the texture on the wrong GPU context and draw nothing, with no
 * error anywhere. So the calls that own resources say which app they mean, and
 * this is how they honour it.
 *
 * **Pass `saved` and restore it afterwards.** Switching contexts and leaving
 * them switched is worse than not switching at all: freeing an image belonging
 * to one window in the middle of *another* window's frame would leave that
 * frame to be submitted into the wrong context, and it would come out blank.
 * That is not hypothetical — a garbage collector picks the moment. `saved` may
 * be NULL only where the caller genuinely does not care what was current.
 */
int rgame_app_gl_make_current(rgame_app *app, rgame_gl_context_save *saved);

/* Puts back what `make_current` displaced. Safe with NULL and with a save that
 * captured "no context current". */
void rgame_app_gl_restore(const rgame_gl_context_save *saved);

/*
 * Keeps the app *struct* alive while something else still points at it.
 *
 * This is not a way to keep the window open — `rgame_app_destroy` closes the
 * window and context immediately however many references are outstanding. It
 * only delays freeing the memory, so that a holder which outlives the app
 * finds a valid pointer whose context is gone (make_current answers 0) instead
 * of reading freed memory.
 *
 * Every retain needs exactly one release. image.c is the only caller: a Ruby
 * image and its app can become garbage in the same collection, and nothing
 * says which gets swept first.
 */
void rgame_app_gl_retain(rgame_app *app);
void rgame_app_gl_release(rgame_app *app);

/*
 * Queues `teardown(object)` for the thread that created `app`, when the caller
 * is on any other thread, and returns 1: the caller must then not tear down
 * itself. Returns 0 on the app's own thread, and for a NULL app, where the
 * caller goes ahead.
 *
 * Every destroy that ends in SDL or GL starts with this: rgame_app_destroy,
 * and an image's or a font's, since a texture lives in its app's context. The
 * app's thread runs the queue in rgame_app_destroy_handed_back.
 */
int rgame_app_hand_back(rgame_app *app, rgame_teardown_fn teardown, void *object);

#endif /* RGAME_APP_GL_H */
