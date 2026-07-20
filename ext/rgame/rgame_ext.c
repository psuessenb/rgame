/*
 * rgame_ext.c — the Ruby C extension glue for the rgame core engine.
 *
 * This is the ONLY file where Ruby-extension concerns (ruby.h, VALUE, the GC)
 * meet the engine. Like src/main.c, it talks exclusively to the public API in
 * rgame/core.h and never reaches into the opaque rgame_app struct. src/main.c
 * drives the engine from a C main(); this file drives the same seams from
 * Ruby, which is the whole point of keeping SDL/GL out of core.h.
 *
 * Ruby surface it defines:
 *
 *   app = Rgame::App.new(width, height, title)
 *   app.run(update_proc, draw_proc, needs_redraw_proc = nil)
 *   app.ticks_ms   # => Integer
 *   app.fps        # => Float
 */

#include <ruby.h>

#include "rgame/core.h"

/*
 * Cached interned identifiers. rb_intern turns a name into an ID (Ruby's
 * interned-symbol integer); doing it once at load time instead of on every
 * callback keeps the per-frame path cheap. The "@"-prefixed ones name the
 * instance variables we stash the callbacks in.
 */
static ID id_iv_update;
static ID id_iv_draw;
static ID id_iv_needs_redraw;
static ID id_call;

/* ------------------------------------------------------------------------- *
 * rgame_app lifetime, wrapped as a Ruby object
 * ------------------------------------------------------------------------- */

/*
 * TypedData is Ruby's mechanism for letting a Ruby object own a raw C pointer.
 * We give it a "free" function so that when the Ruby App object is garbage
 * collected, Ruby tears down the SDL window / GL context for us by calling the
 * public destroy function. rgame_app_destroy is NULL-safe, so an App that was
 * allocated but never initialized frees cleanly too.
 */
static void app_free(void *ptr) {
    rgame_app_destroy((rgame_app *)ptr);
}

static const rb_data_type_t app_data_type = {
    .wrap_struct_name = "rgame_app",
    .function = {
        .dmark = NULL,          /* nothing Ruby-visible to mark inside the C struct */
        .dfree = app_free,
        .dsize = NULL,
    },
    .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

/* Pull the C pointer back out of the Ruby object, raising if it's not set up. */
static rgame_app *app_unwrap(VALUE self) {
    rgame_app *app;
    TypedData_Get_Struct(self, rgame_app, &app_data_type, app);
    if (!app) {
        rb_raise(rb_eRuntimeError, "rgame app is not initialized");
    }
    return app;
}

/*
 * alloc/initialize are split the Ruby way: alloc creates the (empty) wrapper
 * object, initialize fills it in. We wrap NULL first, then create the real app
 * in #initialize and store it — so a failure in the middle still leaves a
 * valid, freeable object.
 */
static VALUE app_alloc(VALUE klass) {
    return TypedData_Wrap_Struct(klass, &app_data_type, NULL);
}

static VALUE app_initialize(VALUE self, VALUE width, VALUE height, VALUE title) {
    rgame_app *app = rgame_app_create(NUM2INT(width), NUM2INT(height),
                                      StringValueCStr(title));
    if (!app) {
        rb_raise(rb_eRuntimeError, "failed to create rgame app");
    }
    /* Store the pointer into the already-wrapped object. */
    RTYPEDDATA_DATA(self) = app;
    return self;
}

/* ------------------------------------------------------------------------- *
 * Callback trampolines
 *
 * rgame_app_run takes plain C function pointers and an opaque userdata. We pass
 * the App's own VALUE as userdata, then in each trampoline read the Ruby proc
 * back out of the instance variable and `.call` it. self stays GC-safe for the
 * whole run because it's a live local on the C stack while rgame_app_run runs,
 * and Ruby's GC conservatively scans the C stack.
 *
 * KNOWN LIMITATION (scaffold): if a Ruby callback raises, rb_funcall does a
 * longjmp straight up through rgame_app_run's C frame — the loop won't unwind
 * cleanly (the window is still torn down later by app_free at GC time). The
 * proper fix is to run each callback under rb_protect and stop the loop on a
 * caught exception; deferred until the callbacks actually do real work.
 * ------------------------------------------------------------------------- */

static void update_trampoline(void *userdata, double dt_seconds) {
    VALUE self = (VALUE)userdata;
    VALUE cb = rb_ivar_get(self, id_iv_update);
    if (!NIL_P(cb)) {
        rb_funcall(cb, id_call, 1, DBL2NUM(dt_seconds));
    }
}

static void draw_trampoline(void *userdata) {
    VALUE self = (VALUE)userdata;
    VALUE cb = rb_ivar_get(self, id_iv_draw);
    if (!NIL_P(cb)) {
        rb_funcall(cb, id_call, 0);
    }
}

static int needs_redraw_trampoline(void *userdata) {
    VALUE self = (VALUE)userdata;
    VALUE cb = rb_ivar_get(self, id_iv_needs_redraw);
    if (NIL_P(cb)) {
        return 1; /* mirrors passing NULL to the C API: always redraw */
    }
    return RTEST(rb_funcall(cb, id_call, 0)) ? 1 : 0;
}

/* ------------------------------------------------------------------------- *
 * app.run(update, draw, needs_redraw = nil)
 * ------------------------------------------------------------------------- */

static VALUE app_run(int argc, VALUE *argv, VALUE self) {
    VALUE update, draw, needs_redraw;
    /* "21" = 2 required args, 1 optional. */
    rb_scan_args(argc, argv, "21", &update, &draw, &needs_redraw);

    /*
     * Stash the callables on the object. Two jobs at once: the trampolines
     * read them back from here, and because they're ivars on this live object
     * the GC keeps them alive for the whole run without a custom mark function.
     */
    rb_ivar_set(self, id_iv_update, update);
    rb_ivar_set(self, id_iv_draw, draw);
    rb_ivar_set(self, id_iv_needs_redraw, needs_redraw);

    rgame_app *app = app_unwrap(self);
    rgame_app_run(app, update_trampoline, draw_trampoline,
                  NIL_P(needs_redraw) ? NULL : needs_redraw_trampoline,
                  (void *)self);

    return self;
}

static VALUE app_ticks_ms(VALUE self) {
    return UINT2NUM(rgame_app_ticks_ms(app_unwrap(self)));
}

static VALUE app_fps(VALUE self) {
    return DBL2NUM(rgame_app_fps(app_unwrap(self)));
}

/* ------------------------------------------------------------------------- *
 * Entry point. Ruby calls Init_<name> when the .so is required; the name must
 * match create_makefile("rgame") in extconf.rb.
 * ------------------------------------------------------------------------- */

void Init_rgame(void) {
    id_iv_update = rb_intern("@update");
    id_iv_draw = rb_intern("@draw");
    id_iv_needs_redraw = rb_intern("@needs_redraw");
    id_call = rb_intern("call");

    VALUE mRgame = rb_define_module("Rgame");
    VALUE cApp = rb_define_class_under(mRgame, "App", rb_cObject);

    rb_define_alloc_func(cApp, app_alloc);
    rb_define_method(cApp, "initialize", app_initialize, 3);
    rb_define_method(cApp, "run", app_run, -1);
    rb_define_method(cApp, "ticks_ms", app_ticks_ms, 0);
    rb_define_method(cApp, "fps", app_fps, 0);
}
