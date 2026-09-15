/*
 * virtual_gamepad_ext.c — the Ruby binding for RGame::Core::VirtualGamepad.
 *
 *   pad = RGame::Core::VirtualGamepad.new   # needs an open App
 *   pad.set_button(0, true)                  # SDL_CONTROLLER_BUTTON_A down
 *   pad.button_down?(0)                      # => true
 *   pad.detach
 *
 * Test-only, and named so, like Audio.debug_live_sounds. The engine side is
 * input/virtual_gamepad.c, which says why this belongs in the extension. This
 * file checks arguments and turns the engine's "stale" and "refused" answers
 * into exceptions; how long to wait for a press to land, and whether presses
 * land at all on a given machine, is the spec harness's business
 * (spec_core/support/virtual_gamepad.rb).
 */

#include "ruby/core_ext.h"

#include "rgame/core.h"

typedef struct {
    rgame_virtual_gamepad *pad;
} rgame_virtual_gamepad_ref;

/* Frees the handle only. Detaching from inside the collector would raise a
 * device-removed event at whatever moment GC happened to run, and after the
 * last App has gone SDL would be touched after SDL_Quit. */
static void virtual_gamepad_ref_free(void *ptr) {
    rgame_virtual_gamepad_ref *ref = ptr;
    rgame_virtual_gamepad_free(ref->pad);
    xfree(ref);
}

static size_t virtual_gamepad_ref_size(const void *ptr) {
    (void)ptr;
    return sizeof(rgame_virtual_gamepad_ref);
}

static const rb_data_type_t virtual_gamepad_data_type = {
    .wrap_struct_name = "rgame_virtual_gamepad",
    .function = {
        .dfree = virtual_gamepad_ref_free,
        .dsize = virtual_gamepad_ref_size,
    },
    .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

/* The pad behind `self`, raising when it can no longer be used: never
 * initialized, or attached during a run of SDL that has since ended. */
static rgame_virtual_gamepad *virtual_gamepad_live(VALUE self) {
    rgame_virtual_gamepad_ref *ref;
    TypedData_Get_Struct(self, rgame_virtual_gamepad_ref, &virtual_gamepad_data_type, ref);
    if (!ref->pad) {
        rb_raise(rb_eRuntimeError, "virtual gamepad is not initialized");
    }
    if (rgame_virtual_gamepad_stale(ref->pad)) {
        rb_raise(rb_eRuntimeError,
                 "virtual gamepad outlived SDL: every App was destroyed after it was attached");
    }
    return ref->pad;
}

static VALUE virtual_gamepad_alloc(VALUE klass) {
    rgame_virtual_gamepad_ref *ref;
    VALUE object = TypedData_Make_Struct(klass, rgame_virtual_gamepad_ref,
                                         &virtual_gamepad_data_type, ref);
    ref->pad = NULL;
    return object;
}

/* VirtualGamepad.new — plugs in a pad. Raises when no App is open. */
static VALUE virtual_gamepad_initialize(VALUE self) {
    rgame_virtual_gamepad_ref *ref;
    TypedData_Get_Struct(self, rgame_virtual_gamepad_ref, &virtual_gamepad_data_type, ref);
    if (ref->pad) {
        rb_raise(rb_eRuntimeError, "virtual gamepad is already attached");
    }

    rgame_virtual_gamepad *pad = rgame_virtual_gamepad_attach();
    if (!pad) {
        rb_raise(rb_eRuntimeError, "cannot attach a virtual gamepad: %s",
                 rgame_virtual_gamepad_error());
    }
    ref->pad = pad;
    return self;
}

/*
 * #set_button(button, down) — `button` is SDL's controller button number, the
 * same number RGame::Util::Controls' PAD_ ids add to the gamepad range. True
 * when SDL accepted the change, which SDL may apply only on a later pump.
 */
static VALUE virtual_gamepad_set_button(VALUE self, VALUE button, VALUE down) {
    rgame_virtual_gamepad *pad = virtual_gamepad_live(self);
    int result = rgame_virtual_gamepad_set_button(pad, NUM2INT(button), RTEST(down));
    return result == 0 ? Qtrue : Qfalse;
}

/* #set_axis(axis, value) — `value` in -32768..32767, SDL's own axis range. */
static VALUE virtual_gamepad_set_axis(VALUE self, VALUE axis, VALUE value) {
    rgame_virtual_gamepad *pad = virtual_gamepad_live(self);
    int raw = NUM2INT(value);
    if (raw < -32768 || raw > 32767) {
        rb_raise(rb_eRangeError, "axis value %d is outside -32768..32767", raw);
    }
    return rgame_virtual_gamepad_set_axis(pad, NUM2INT(axis), raw) == 0 ? Qtrue : Qfalse;
}

/* #button_down?(button) — the raw joystick button, before controller mapping. */
static VALUE virtual_gamepad_button_down_p(VALUE self, VALUE button) {
    rgame_virtual_gamepad *pad = virtual_gamepad_live(self);
    return rgame_virtual_gamepad_button_down(pad, NUM2INT(button)) ? Qtrue : Qfalse;
}

/* #game_controller? — whether SDL has a mapping for the pad, which an App needs
 * before it seats one. */
static VALUE virtual_gamepad_game_controller_p(VALUE self) {
    return rgame_virtual_gamepad_is_game_controller(virtual_gamepad_live(self)) ? Qtrue : Qfalse;
}

static VALUE virtual_gamepad_attached_p(VALUE self) {
    return rgame_virtual_gamepad_attached(virtual_gamepad_live(self)) ? Qtrue : Qfalse;
}

/* #detach — unplugs the pad. Does nothing the second time, or once SDL has shut
 * down, since the pad went with it. */
static VALUE virtual_gamepad_detach(VALUE self) {
    rgame_virtual_gamepad_ref *ref;
    TypedData_Get_Struct(self, rgame_virtual_gamepad_ref, &virtual_gamepad_data_type, ref);
    if (ref->pad) {
        rgame_virtual_gamepad_detach(ref->pad);
    }
    return Qnil;
}

/* VirtualGamepad.pump — runs SDL's event pump and applies pending pad state. */
static VALUE virtual_gamepad_s_pump(VALUE klass) {
    (void)klass;
    rgame_virtual_gamepad_pump();
    return Qnil;
}

/* VirtualGamepad.sdl_error — what SDL last said when it refused something. */
static VALUE virtual_gamepad_s_sdl_error(VALUE klass) {
    (void)klass;
    return rb_utf8_str_new_cstr(rgame_virtual_gamepad_error());
}

void rgame_init_virtual_gamepad(VALUE mCore) {
    VALUE cVirtualGamepad = rb_define_class_under(mCore, "VirtualGamepad", rb_cObject);

    rb_define_alloc_func(cVirtualGamepad, virtual_gamepad_alloc);
    rb_define_method(cVirtualGamepad, "initialize", virtual_gamepad_initialize, 0);
    rb_define_method(cVirtualGamepad, "set_button", virtual_gamepad_set_button, 2);
    rb_define_method(cVirtualGamepad, "set_axis", virtual_gamepad_set_axis, 2);
    rb_define_method(cVirtualGamepad, "button_down?", virtual_gamepad_button_down_p, 1);
    rb_define_method(cVirtualGamepad, "game_controller?", virtual_gamepad_game_controller_p, 0);
    rb_define_method(cVirtualGamepad, "attached?", virtual_gamepad_attached_p, 0);
    rb_define_method(cVirtualGamepad, "detach", virtual_gamepad_detach, 0);
    rb_define_singleton_method(cVirtualGamepad, "pump", virtual_gamepad_s_pump, 0);
    rb_define_singleton_method(cVirtualGamepad, "sdl_error", virtual_gamepad_s_sdl_error, 0);
}
