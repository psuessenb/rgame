#ifndef RGAME_CORE_EXT_H
#define RGAME_CORE_EXT_H

#include <ruby.h>

#include "rgame/core.h"

/*
 * Each Ruby-visible class in this extension beyond App exposes one init
 * function, and core_ext.c calls them all — the same shape as
 * ext/rgame_util/util_ext.h. Adding a class means adding a file and one line
 * there, rather than growing one file that owns everything.
 *
 * App itself still lives in core_ext.c: it is the entry point's own subject,
 * and the callback trampolines that drive the main loop are inseparable from
 * it.
 */

void rgame_init_image(VALUE mCore);

/*
 * The engine handle behind a Ruby RGame::Core::App. Raises TypeError if the
 * object is not one — TypedData does that check itself, which is why anything
 * needing an app takes the Ruby object and calls this rather than duck-typing.
 */
rgame_app *rgame_app_unwrap(VALUE app);

#endif /* RGAME_CORE_EXT_H */
