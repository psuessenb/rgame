/*
 * core_ext.c — the Ruby C extension glue for the rgame core engine.
 *
 * This is the ONLY file where Ruby-extension concerns (ruby.h, VALUE, the GC)
 * meet the engine. Like src/main.c, it talks exclusively to the public API in
 * rgame/core.h and never reaches into the opaque rgame_app struct. src/main.c
 * drives the engine from a C main(); this file drives the same seams from
 * Ruby, which is the whole point of keeping SDL/GL out of core.h.
 *
 * Everything here lands under RGame::Core — the namespace for code that
 * depends on SDL/OpenGL. Anything that doesn't belongs in RGame::Util instead
 * (ext/rgame_util/), which links no graphics libraries at all.
 *
 * App is designed to be *subclassed*: the engine calls back into methods on
 * the object itself, so a game overrides the ones it cares about and inherits
 * no-ops for the rest.
 *
 *   class MyGame < RGame::Core::App
 *     def initialize = super(width: 800, height: 600, caption: 'demo')
 *     def update(dt); end        # one fixed simulation tick
 *     def draw; end              # render one frame
 *     def needs_redraw?; end     # false skips the draw
 *     def button_down(id); end   # discrete key press
 *     def button_up(id); end
 *     def frame_begin; end       # once per frame, before the tick batch
 *     def resize(w, h); end
 *     def gamepad_connected(slot); end
 *     def gamepad_disconnected(slot); end
 *   end
 *
 *   MyGame.new.run
 *
 * Inherited from App: #close, #width, #height, #caption, #caption=,
 * #ticks_ms, #fps.
 */

#include <ruby.h>

#include "core_ext.h"
#include "rgame/core.h"

/*
 * Cached interned identifiers. rb_intern turns a name into an ID (Ruby's
 * interned-symbol integer); doing it once at load time instead of on every
 * callback keeps the per-frame path cheap.
 */
static ID id_frame_begin;
static ID id_update;
static ID id_draw;
static ID id_needs_redraw;
static ID id_button_down;
static ID id_button_up;
static ID id_resize;
static ID id_gamepad_connected;
static ID id_gamepad_disconnected;
static ID id_width;
static ID id_height;
static ID id_caption;

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

/* Pull the C pointer back out of the Ruby object, raising if it's not set up.
 * Also the accessor other files in this extension use (see core_ext.h), which
 * is why it is not static: TypedData_Get_Struct raises TypeError on anything
 * that is not an App, so callers get that check for free. */
rgame_app *rgame_app_unwrap(VALUE self) {
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

/* App.new(width:, height:, caption:) — keyword arguments, matching the shape a
 * subclass's own initialize will forward to via super. */
static VALUE app_initialize(int argc, VALUE *argv, VALUE self) {
    VALUE opts = Qnil;
    rb_scan_args(argc, argv, "0:", &opts); /* no positional args, keywords only */
    if (NIL_P(opts)) {
        rb_raise(rb_eArgError, "missing keywords: :width, :height, :caption");
    }

    const ID keys[3] = { id_width, id_height, id_caption };
    VALUE values[3];
    /* 3 required, 0 optional: raises on a missing or unknown keyword. */
    rb_get_kwargs(opts, keys, 3, 0, values);

    rgame_app *app = rgame_app_create(NUM2INT(values[0]), NUM2INT(values[1]),
                                      StringValueCStr(values[2]));
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
 * rgame_app_run takes plain C function pointers and an opaque userdata. We
 * pass a run_state living on app_run's C stack, and each trampoline calls the
 * corresponding method on the App object.
 *
 * Exception safety is the interesting part. A Ruby callback may raise, and a
 * raise is a longjmp — it would tear straight through rgame_app_run's C frame,
 * skipping the rest of the loop and leaving the SDL window up until the GC
 * eventually collects the App. So every callback runs under rb_protect, which
 * catches the unwind and hands back a non-zero tag instead. We stash the
 * exception, ask the engine to close, let rgame_app_run return normally, and
 * only then re-raise from #run — by which point the C loop has unwound cleanly
 * on its own terms.
 *
 * Both VALUEs in run_state live on the C stack, which Ruby's GC scans
 * conservatively, so the captured exception stays alive without a mark
 * function.
 * ------------------------------------------------------------------------- */

typedef struct {
    VALUE self;
    rgame_app *app;
    int failed;      /* set once a callback has unwound; suppresses further calls */
    VALUE exception; /* what to re-raise once the loop has exited */
} run_state;

/* rb_protect and rb_rescue2 can only call a function taking one VALUE, so the
 * call is packed into a struct and passed by pointer. `caught` is the way the
 * rescue handler reports back. */
typedef struct {
    VALUE self;
    ID method;
    int argc;
    const VALUE *argv;
    VALUE caught; /* the exception, if the callback raised one */
} funcall_args;

static VALUE do_funcall(VALUE arg) {
    const funcall_args *a = (const funcall_args *)arg;
    return rb_funcallv(a->self, a->method, a->argc, a->argv);
}

static VALUE capture_exception(VALUE arg, VALUE err) {
    funcall_args *a = (funcall_args *)arg;
    a->caught = err;
    return Qnil;
}

/*
 * Run the callback, turning any exception into a plain value handed back via
 * `caught`. rb_rescue2 is used rather than reading rb_errinfo() after an
 * rb_protect, because errinfo is only safe to inspect when the unwind really
 * was an exception — see protected_call.
 */
static VALUE call_with_rescue(VALUE arg) {
    return rb_rescue2(do_funcall, arg, capture_exception, arg, rb_eException, (VALUE)0);
}

static VALUE protected_call(run_state *rs, ID method, int argc, const VALUE *argv) {
    /* Already unwinding: run no further Ruby, just let the loop finish. */
    if (rs->failed) {
        return Qnil;
    }

    funcall_args args = { rs->self, method, argc, argv, Qnil };
    int state = 0;
    VALUE result = rb_protect(call_with_rescue, (VALUE)&args, &state);

    if (state) {
        /*
         * rb_rescue2 already handled every *exception*, so reaching here means
         * a non-exception unwind: throw, break, next or return crossing the C
         * frame. Those cannot be deferred and re-raised later — rb_protect
         * pops the tag holding the jump's target as it returns, so replaying
         * it afterwards jumps into freed state.
         *
         * Nor can the pending errinfo be inspected to find out what happened:
         * CRuby stashes an internal throw-data object there, which is a
         * T_IMEMO rather than a real object, so even asking for its class
         * walks garbage. (Both of those were found the hard way, as
         * segfaults.) So errinfo is cleared without ever being read, and the
         * situation is reported as an ordinary error.
         */
        rb_set_errinfo(Qnil);
        rs->failed = 1;
        rs->exception = rb_exc_new_cstr(
            rb_eRuntimeError,
            "non-local exit (throw/break/return) crossed the rgame main loop; "
            "call #close to stop the loop instead");
        rgame_app_close(rs->app);
        return Qnil;
    }

    if (!NIL_P(args.caught)) {
        rs->failed = 1;
        rs->exception = args.caught;
        rgame_app_close(rs->app);
        return Qnil;
    }

    return result;
}

static void tramp_frame_begin(void *userdata) {
    protected_call((run_state *)userdata, id_frame_begin, 0, NULL);
}

static void tramp_update(void *userdata, double dt_seconds) {
    VALUE dt = DBL2NUM(dt_seconds);
    protected_call((run_state *)userdata, id_update, 1, &dt);
}

static void tramp_draw(void *userdata) {
    protected_call((run_state *)userdata, id_draw, 0, NULL);
}

static int tramp_needs_redraw(void *userdata) {
    VALUE result = protected_call((run_state *)userdata, id_needs_redraw, 0, NULL);
    return RTEST(result) ? 1 : 0;
}

static void tramp_button_down(void *userdata, int button_id) {
    VALUE id = INT2NUM(button_id);
    protected_call((run_state *)userdata, id_button_down, 1, &id);
}

static void tramp_button_up(void *userdata, int button_id) {
    VALUE id = INT2NUM(button_id);
    protected_call((run_state *)userdata, id_button_up, 1, &id);
}

static void tramp_resize(void *userdata, int width, int height) {
    VALUE args[2] = { INT2NUM(width), INT2NUM(height) };
    protected_call((run_state *)userdata, id_resize, 2, args);
}

static void tramp_gamepad_connected(void *userdata, int slot) {
    VALUE arg = INT2NUM(slot);
    protected_call((run_state *)userdata, id_gamepad_connected, 1, &arg);
}

static void tramp_gamepad_disconnected(void *userdata, int slot) {
    VALUE arg = INT2NUM(slot);
    protected_call((run_state *)userdata, id_gamepad_disconnected, 1, &arg);
}

/* ------------------------------------------------------------------------- *
 * app.run
 * ------------------------------------------------------------------------- */

static VALUE app_run(VALUE self) {
    rgame_app *app = rgame_app_unwrap(self);
    run_state rs = { self, app, 0, Qnil };

    rgame_app_callbacks callbacks = {
        .frame_begin = tramp_frame_begin,
        .update = tramp_update,
        .needs_redraw = tramp_needs_redraw,
        .draw = tramp_draw,
        .button_down = tramp_button_down,
        .button_up = tramp_button_up,
        .resize = tramp_resize,
        .gamepad_connected = tramp_gamepad_connected,
        .gamepad_disconnected = tramp_gamepad_disconnected,
        .userdata = &rs,
    };

    rgame_app_run(app, &callbacks);

    /* A callback unwound: the loop has now exited on its own terms, so it is
     * safe to raise. Class, message and backtrace are the original ones. */
    if (rs.failed) {
        rb_exc_raise(rs.exception);
    }

    return self;
}

/* ------------------------------------------------------------------------- *
 * Window queries and control
 * ------------------------------------------------------------------------- */

static VALUE app_close(VALUE self) {
    rgame_app_close(rgame_app_unwrap(self));
    return self;
}

static VALUE app_width(VALUE self) {
    return INT2NUM(rgame_app_width(rgame_app_unwrap(self)));
}

static VALUE app_height(VALUE self) {
    return INT2NUM(rgame_app_height(rgame_app_unwrap(self)));
}

static VALUE app_caption(VALUE self) {
    const char *title = rgame_app_title(rgame_app_unwrap(self));
    return rb_utf8_str_new_cstr(title ? title : "");
}

static VALUE app_set_caption(VALUE self, VALUE title) {
    rgame_app_set_title(rgame_app_unwrap(self), StringValueCStr(title));
    return title;
}

/*
 * Raw input queries. These take the numeric device and button/axis ids from
 * RGame::Core::Input rather than symbolic action names — turning `:fire` into
 * an id is the binding table's job, and that lives in Ruby (see
 * lib/rgame/core/input.rb) because it is configuration, not mechanism.
 */
static VALUE app_input_down_p(VALUE self, VALUE device, VALUE button_id) {
    return rgame_app_input_down(rgame_app_unwrap(self), NUM2INT(device), NUM2INT(button_id))
               ? Qtrue
               : Qfalse;
}

static VALUE app_input_axis(VALUE self, VALUE device, VALUE axis_id) {
    return DBL2NUM(rgame_app_input_axis(rgame_app_unwrap(self), NUM2INT(device), NUM2INT(axis_id)));
}

/*
 * Gamepad readout. Named `gamepad_present?` rather than `gamepad_connected?`
 * on purpose: `gamepad_connected` is already the hot-plug *callback* a subclass
 * overrides, and two methods differing only by a trailing `?` is a trap. The
 * friendly name lives on RGame::Core::Gamepad, which reads better anyway.
 */
static VALUE app_gamepad_present_p(VALUE self, VALUE slot) {
    return rgame_app_gamepad_connected(rgame_app_unwrap(self), NUM2INT(slot)) ? Qtrue : Qfalse;
}

/* nil for an empty slot, or for a pad SDL has no name for. */
static VALUE app_gamepad_name(VALUE self, VALUE slot) {
    const char *name = rgame_app_gamepad_name(rgame_app_unwrap(self), NUM2INT(slot));
    return name ? rb_utf8_str_new_cstr(name) : Qnil;
}

static VALUE app_gamepad_count(VALUE self) {
    return INT2NUM(rgame_app_gamepad_count(rgame_app_unwrap(self)));
}

static VALUE app_ticks_ms(VALUE self) {
    return UINT2NUM(rgame_app_ticks_ms(rgame_app_unwrap(self)));
}

static VALUE app_fps(VALUE self) {
    return DBL2NUM(rgame_app_fps(rgame_app_unwrap(self)));
}

/* ------------------------------------------------------------------------- *
 * Default callbacks
 *
 * Defined so a subclass only overrides the hooks it actually cares about, and
 * so the trampolines can call unconditionally without checking respond_to?.
 * ------------------------------------------------------------------------- */

static VALUE app_default_frame_begin(VALUE self) {
    (void)self;
    return Qnil;
}

static VALUE app_default_update(VALUE self, VALUE dt_seconds) {
    (void)self;
    (void)dt_seconds;
    return Qnil;
}

static VALUE app_default_draw(VALUE self) {
    (void)self;
    return Qnil;
}

/* Default is "always redraw", matching a NULL needs_redraw in the C API. */
static VALUE app_default_needs_redraw(VALUE self) {
    (void)self;
    return Qtrue;
}

static VALUE app_default_button(VALUE self, VALUE button_id) {
    (void)self;
    (void)button_id;
    return Qnil;
}

static VALUE app_default_resize(VALUE self, VALUE width, VALUE height) {
    (void)self;
    (void)width;
    (void)height;
    return Qnil;
}

static VALUE app_default_gamepad(VALUE self, VALUE slot) {
    (void)self;
    (void)slot;
    return Qnil;
}

/* ------------------------------------------------------------------------- *
 * Entry point. Ruby calls Init_<basename of the required path> when the .so is
 * loaded; we require it as "rgame/core_ext", so this must be
 * Init_core_ext, matching create_makefile("rgame/core_ext") in
 * extconf.rb.
 * ------------------------------------------------------------------------- */

void Init_core_ext(void) {
    id_frame_begin = rb_intern("frame_begin");
    id_update = rb_intern("update");
    id_draw = rb_intern("draw");
    id_needs_redraw = rb_intern("needs_redraw?");
    id_button_down = rb_intern("button_down");
    id_button_up = rb_intern("button_up");
    id_resize = rb_intern("resize");
    id_gamepad_connected = rb_intern("gamepad_connected");
    id_gamepad_disconnected = rb_intern("gamepad_disconnected");
    id_width = rb_intern("width");
    id_height = rb_intern("height");
    id_caption = rb_intern("caption");

    /*
     * rb_define_module is idempotent — it returns the existing RGame if some
     * other extension or Ruby file defined it first, so load order between the
     * two extensions doesn't matter.
     */
    VALUE mRGame = rb_define_module("RGame");
    VALUE mCore = rb_define_module_under(mRGame, "Core");
    VALUE cApp = rb_define_class_under(mCore, "App", rb_cObject);

    rb_define_alloc_func(cApp, app_alloc);
    rb_define_method(cApp, "initialize", app_initialize, -1);
    rb_define_method(cApp, "run", app_run, 0);

    rb_define_method(cApp, "close", app_close, 0);
    rb_define_method(cApp, "width", app_width, 0);
    rb_define_method(cApp, "height", app_height, 0);
    rb_define_method(cApp, "caption", app_caption, 0);
    rb_define_method(cApp, "caption=", app_set_caption, 1);
    rb_define_method(cApp, "ticks_ms", app_ticks_ms, 0);
    rb_define_method(cApp, "fps", app_fps, 0);
    rb_define_method(cApp, "input_down?", app_input_down_p, 2);
    rb_define_method(cApp, "input_axis", app_input_axis, 2);
    rb_define_method(cApp, "gamepad_present?", app_gamepad_present_p, 1);
    rb_define_method(cApp, "gamepad_name", app_gamepad_name, 1);
    rb_define_method(cApp, "gamepad_count", app_gamepad_count, 0);


    rb_define_method(cApp, "frame_begin", app_default_frame_begin, 0);
    rb_define_method(cApp, "update", app_default_update, 1);
    rb_define_method(cApp, "draw", app_default_draw, 0);
    rb_define_method(cApp, "needs_redraw?", app_default_needs_redraw, 0);
    rb_define_method(cApp, "button_down", app_default_button, 1);
    rb_define_method(cApp, "button_up", app_default_button, 1);
    rb_define_method(cApp, "resize", app_default_resize, 2);
    rb_define_method(cApp, "gamepad_connected", app_default_gamepad, 1);
    rb_define_method(cApp, "gamepad_disconnected", app_default_gamepad, 1);

    rgame_init_image(mCore);
    rgame_init_renderer(mCore);
    rgame_init_recording(mCore);
    rgame_init_font(mCore);
    rgame_init_audio(mCore);
}
