/*
 * color_ext.c — the Ruby binding for RGame::Util::Color.
 *
 * The arithmetic lives in color.{c,h}, which includes no ruby.h and is covered
 * directly by the Check suite. This file is only the wrapper: argument
 * checking, and the value semantics Ruby expects of a value object.
 *
 * Instances are frozen. A colour is a value, and a mutable one shared between
 * two sprites would be a bug waiting for someone to tint one of them.
 */

#include "util_ext.h"

#include "color.h"

/*
 * TypedData lets a Ruby object own a raw C value. The payload here is a single
 * uint32, small enough that it could have been an instance variable — but
 * going through TypedData keeps the unwrap a pointer read rather than an ivar
 * lookup, and matches how every other C-backed class in the project is built.
 */
static const rb_data_type_t color_data_type = {
    .wrap_struct_name = "rgame_color",
    .function = {
        .dmark = NULL, /* no Ruby objects inside */
        .dfree = RUBY_TYPED_DEFAULT_FREE,
        .dsize = NULL,
    },
    .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

static rgame_color color_unwrap(VALUE self) {
    rgame_color *color;
    TypedData_Get_Struct(self, rgame_color, &color_data_type, color);
    return *color;
}

static VALUE color_wrap(VALUE klass, rgame_color value) {
    rgame_color *storage;
    VALUE object = TypedData_Make_Struct(klass, rgame_color, &color_data_type, storage);
    *storage = value;
    return rb_obj_freeze(object);
}

/* Ruby is stricter than the C layer, which clamps: a Ruby caller passing 300
 * has a bug, and silently turning it into 255 hides it. */
static int component(VALUE value, const char *name) {
    int number = NUM2INT(value);
    if (number < 0 || number > 255) {
        rb_raise(rb_eArgError, "%s must be in 0..255, got %d", name, number);
    }
    return number;
}

/* Color.new(r, g, b, a = 255) */
static VALUE color_s_new(int argc, VALUE *argv, VALUE klass) {
    VALUE r, g, b, a;
    rb_scan_args(argc, argv, "31", &r, &g, &b, &a);

    return color_wrap(klass,
                      rgame_color_rgba(component(r, "red"), component(g, "green"),
                                       component(b, "blue"),
                                       NIL_P(a) ? 255 : component(a, "alpha")));
}

/* Color.from_packed(0xRRGGBBAA) */
static VALUE color_s_from_packed(VALUE klass, VALUE packed) {
    unsigned long value = NUM2ULONG(packed);
    if (value > 0xFFFFFFFFul) {
        rb_raise(rb_eArgError, "packed colour must fit in 32 bits");
    }
    return color_wrap(klass, (rgame_color)value);
}

/*
 * Color.coerce(nil | [r,g,b] | [r,g,b,a] | Color) -> Color
 *
 * Every draw call accepts a colour in any of those forms, so the conversion
 * lives in one place rather than being repeated in each primitive. nil means
 * white, matching what an untinted draw has always meant.
 */
static VALUE color_s_coerce(VALUE klass, VALUE value) {
    if (NIL_P(value)) {
        return rb_const_get(klass, rb_intern("WHITE"));
    }
    if (rb_obj_is_kind_of(value, klass)) {
        return value;
    }
    if (RB_TYPE_P(value, T_ARRAY)) {
        long length = RARRAY_LEN(value);
        if (length != 3 && length != 4) {
            rb_raise(rb_eArgError, "colour array must be [r, g, b] or [r, g, b, a], got %ld elements",
                     length);
        }
        VALUE alpha = length == 4 ? rb_ary_entry(value, 3) : INT2FIX(255);
        VALUE args[4] = { rb_ary_entry(value, 0), rb_ary_entry(value, 1),
                          rb_ary_entry(value, 2), alpha };
        return color_s_new(4, args, klass);
    }
    rb_raise(rb_eTypeError, "cannot coerce %" PRIsVALUE " into a colour", rb_obj_class(value));
}

static VALUE color_r(VALUE self) { return INT2FIX(rgame_color_r(color_unwrap(self))); }
static VALUE color_g(VALUE self) { return INT2FIX(rgame_color_g(color_unwrap(self))); }
static VALUE color_b(VALUE self) { return INT2FIX(rgame_color_b(color_unwrap(self))); }
static VALUE color_a(VALUE self) { return INT2FIX(rgame_color_a(color_unwrap(self))); }

/* The 0xRRGGBBAA form. This is what the renderer hands to C — note it is *not*
 * what goes into a vertex byte-for-byte; see rgame_color_bytes in color.h. */
static VALUE color_packed(VALUE self) { return UINT2NUM(color_unwrap(self)); }

/* Value semantics: two colours with the same components are the same colour,
 * and eql?/hash follow so a Color works as a Hash key. */
static VALUE color_equal(VALUE self, VALUE other) {
    if (!rb_obj_is_kind_of(other, rb_obj_class(self))) {
        return Qfalse;
    }
    return color_unwrap(self) == color_unwrap(other) ? Qtrue : Qfalse;
}

static VALUE color_hash(VALUE self) {
    return rb_hash(UINT2NUM(color_unwrap(self)));
}

static VALUE color_inspect(VALUE self) {
    rgame_color color = color_unwrap(self);
    return rb_sprintf("#<RGame::Util::Color r=%d g=%d b=%d a=%d>", rgame_color_r(color),
                      rgame_color_g(color), rgame_color_b(color), rgame_color_a(color));
}

void rgame_init_color(VALUE mUtil) {
    VALUE cColor = rb_define_class_under(mUtil, "Color", rb_cObject);

    /* No alloc func: a Color is always built through one of these, so there is
     * no half-initialized state to guard against. */
    rb_undef_alloc_func(cColor);
    rb_define_singleton_method(cColor, "new", color_s_new, -1);
    rb_define_singleton_method(cColor, "rgba", color_s_new, -1);
    rb_define_singleton_method(cColor, "from_packed", color_s_from_packed, 1);
    rb_define_singleton_method(cColor, "coerce", color_s_coerce, 1);

    rb_define_method(cColor, "r", color_r, 0);
    rb_define_method(cColor, "g", color_g, 0);
    rb_define_method(cColor, "b", color_b, 0);
    rb_define_method(cColor, "a", color_a, 0);
    rb_define_method(cColor, "packed", color_packed, 0);
    rb_define_method(cColor, "==", color_equal, 1);
    rb_define_method(cColor, "eql?", color_equal, 1);
    rb_define_method(cColor, "hash", color_hash, 0);
    rb_define_method(cColor, "inspect", color_inspect, 0);
    rb_define_alias(cColor, "to_s", "inspect");

    rb_define_const(cColor, "WHITE", color_wrap(cColor, RGAME_COLOR_WHITE));
    rb_define_const(cColor, "BLACK", color_wrap(cColor, RGAME_COLOR_BLACK));
    rb_define_const(cColor, "TRANSPARENT", color_wrap(cColor, RGAME_COLOR_TRANSPARENT));
}
