/*
 * typeface_ext.c — the Ruby binding for RGame::Util::Typeface.
 *
 * The face lives in typeface.{c,h}, which includes no ruby.h and is covered
 * directly by the Check suite. This file is argument checking and wrapping.
 *
 * It takes bytes, never a path: lib/rgame/util/typeface.rb reads the file, so
 * no file I/O enters this extension, and the path reaches C only to be named in
 * an error.
 */

#include "util_ext.h"

#include "typeface.h"

typedef struct {
    rgame_typeface *typeface;
    size_t font_bytes; /* the face keeps its own copy, reported to the GC */
} rgame_typeface_ref;

static void typeface_ref_free(void *ptr) {
    rgame_typeface_ref *ref = ptr;
    rgame_typeface_close(ref->typeface); /* NULL-safe */
    xfree(ref);
}

static size_t typeface_ref_size(const void *ptr) {
    const rgame_typeface_ref *ref = ptr;
    return sizeof(*ref) + ref->font_bytes;
}

static const rb_data_type_t typeface_data_type = {
    .wrap_struct_name = "rgame_typeface",
    .function = {
        .dmark = NULL, /* no Ruby objects inside */
        .dfree = typeface_ref_free,
        .dsize = typeface_ref_size,
    },
    .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

static VALUE cTypeface;

static const rgame_typeface *typeface_unwrap(VALUE self) {
    rgame_typeface_ref *ref;
    TypedData_Get_Struct(self, rgame_typeface_ref, &typeface_data_type, ref);
    if (!ref->typeface) {
        rb_raise(rb_eRuntimeError, "typeface is not initialized");
    }
    return ref->typeface;
}

static VALUE typeface_alloc(VALUE klass) {
    rgame_typeface_ref *ref;
    VALUE object = TypedData_Make_Struct(klass, rgame_typeface_ref, &typeface_data_type, ref);
    ref->typeface = NULL;
    ref->font_bytes = 0;
    return object;
}

/* Typeface#initialize(bytes, pixel_height, path) — the Ruby half reads the file
 * and passes its path along for the error message. */
static VALUE typeface_initialize(VALUE self, VALUE bytes, VALUE pixel_height, VALUE path) {
    rgame_typeface_ref *ref;
    TypedData_Get_Struct(self, rgame_typeface_ref, &typeface_data_type, ref);
    if (ref->typeface) {
        rb_raise(rb_eRuntimeError, "typeface is already initialized");
    }

    StringValue(bytes);
    int height = NUM2INT(pixel_height);
    if (height <= 0) {
        rb_raise(rb_eArgError, "a typeface needs a positive pixel height, got %d", height);
    }

    size_t length = (size_t)RSTRING_LEN(bytes);
    rgame_typeface *typeface =
        rgame_typeface_open((const unsigned char *)RSTRING_PTR(bytes), length, height);
    RB_GC_GUARD(bytes);
    if (!typeface) {
        rb_raise(rb_const_get(cTypeface, rb_intern("LoadError")),
                 "could not read %" PRIsVALUE " as a TrueType font", path);
    }

    ref->typeface = typeface;
    ref->font_bytes = length;
    return self;
}

/* The size it was opened at, and the amount to step by for a second line. */
static VALUE typeface_height(VALUE self) {
    return INT2NUM(rgame_typeface_height(typeface_unwrap(self)));
}

/*
 * #text_width(string) — how wide the string draws, in pixels.
 *
 * The same walk Core::Font measures and draws with, over the same bytes, so a
 * width taken here is the width drawn there.
 */
static VALUE typeface_text_width(VALUE self, VALUE string) {
    const rgame_typeface *typeface = typeface_unwrap(self);
    StringValue(string);

    double width = rgame_typeface_measure(typeface, RSTRING_PTR(string),
                                          (size_t)RSTRING_LEN(string));
    RB_GC_GUARD(string);
    return DBL2NUM(width);
}

/*
 * #wrap(string, max_width) — the lines the string breaks into at `max_width`
 * pixels, one String per line.
 *
 * Lines break at spaces, and each break takes the space it replaced, so the
 * lines joined with one space give back the string. Every line measures no
 * wider than `max_width`, except a single word wider than the whole line,
 * which comes back whole. An empty string has no lines.
 */
static VALUE typeface_wrap(VALUE self, VALUE string, VALUE max_width) {
    const rgame_typeface *typeface = typeface_unwrap(self);
    StringValue(string);
    float width = (float)NUM2DBL(max_width);

    VALUE lines = rb_ary_new();
    long length = RSTRING_LEN(string);
    if (length == 0) {
        return lines;
    }

    long offset = 0;
    for (;;) {
        size_t fit_length = 0;
        float fit_width = 0.0f;
        rgame_typeface_fit(typeface, RSTRING_PTR(string) + offset, (size_t)(length - offset),
                           width, &fit_length, &fit_width);
        rb_ary_push(lines, rb_str_subseq(string, offset, (long)fit_length));

        offset += (long)fit_length;
        if (offset == length) {
            break;
        }
        offset += 1;
    }

    RB_GC_GUARD(string);
    return lines;
}

static VALUE typeface_inspect(VALUE self) {
    rgame_typeface_ref *ref;
    TypedData_Get_Struct(self, rgame_typeface_ref, &typeface_data_type, ref);
    if (!ref->typeface) {
        return rb_sprintf("#<%" PRIsVALUE " (uninitialized)>", rb_obj_class(self));
    }
    return rb_sprintf("#<%" PRIsVALUE " %dpx>", rb_obj_class(self),
                      rgame_typeface_height(ref->typeface));
}

void rgame_init_typeface(VALUE mUtil) {
    cTypeface = rb_define_class_under(mUtil, "Typeface", rb_cObject);

    /* Raised when a file cannot be read or is not a TrueType font — an everyday
     * condition, so it gets a name a game can rescue. */
    rb_define_class_under(cTypeface, "LoadError", rb_eStandardError);

    rb_define_alloc_func(cTypeface, typeface_alloc);
    rb_define_method(cTypeface, "initialize", typeface_initialize, 3);
    rb_define_method(cTypeface, "height", typeface_height, 0);
    rb_define_method(cTypeface, "text_width", typeface_text_width, 1);
    rb_define_method(cTypeface, "wrap", typeface_wrap, 2);
    rb_define_method(cTypeface, "inspect", typeface_inspect, 0);
}
