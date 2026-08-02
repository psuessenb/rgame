/*
 * util_ext.c — entry point for the graphics-free extension.
 *
 * Ruby calls Init_<basename of the required path> when the .so is loaded; we
 * require it as "rgame/util_ext", so this must be Init_util_ext, matching
 * create_makefile("rgame/util_ext") in extconf.rb.
 *
 * Its only job is to hand the RGame::Util module to each class's init
 * function. Nothing here links SDL or OpenGL, and nothing ever should: the
 * whole point of this extension is that `require "rgame"` costs no graphics
 * libraries. See CLAUDE.md, "The Core / Util split".
 */

#include "util_ext.h"

void Init_util_ext(void) {
    /*
     * rb_define_module is idempotent — it returns the existing RGame if some
     * other extension or Ruby file defined it first, so load order between the
     * two extensions doesn't matter.
     */
    VALUE mRGame = rb_define_module("RGame");
    VALUE mUtil = rb_define_module_under(mRGame, "Util");

    rgame_init_tensor(mUtil);
    rgame_init_color(mUtil);
}
