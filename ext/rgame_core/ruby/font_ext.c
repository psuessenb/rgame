/*
 * font_ext.c — the Ruby binding for RGame::Core::Font.
 *
 *   font = RGame::Core::Font.new(app, RGame::Util::Typeface.default(18))
 *   font.typeface      # => that typeface
 *   font.height        # => 18
 *   font.text_width('Score: 1200')
 *
 * The atlas, the cache and the metrics are in font_atlas.c, atlas.c,
 * glyph_cache.c and ext/rgame_util/typeface.c — three of those four are pure
 * and Check-tested. This file is
 * the wrapper: argument checking, turning a NULL return into an exception that
 * says why, and keeping the app reachable for as long as the font is.
 *
 * A font is always built from a RGame::Util::Typeface. It asks the typeface for
 * its bytes through Ruby and opens its own face from them: the two extensions
 * share no C object, and the same bytes measure the same. The forms that take a
 * size and a path are sugar in lib/rgame/core/font.rb, which builds the
 * typeface first and owns the default path.
 *
 * The C layer has no opinion about where fonts live and there is **no
 * font-name lookup at all**: a font is a file. Asking the operating system for
 * one by name would mean a font-database backend per platform — fontconfig on
 * Linux, CoreText on macOS, GDI on Windows — and a system dependency this
 * engine otherwise does not have. It would also mean text renders differently
 * on different machines, which is a layout bug nobody can reproduce. See
 * vendor/README.md.
 */

#include "ruby/core_ext.h"

#include "text/font_internal.h"
#include "rgame/core.h"

typedef struct {
    rgame_font *font;
    VALUE app_object; /* marked: the atlas pages live in this window's context */
    VALUE typeface;   /* marked: what #typeface answers */
} rgame_font_ref;

static void font_ref_mark(void *ptr) {
    rgame_font_ref *ref = ptr;
    rb_gc_mark(ref->app_object);
    rb_gc_mark(ref->typeface);
}

static void font_ref_free(void *ptr) {
    rgame_font_ref *ref = ptr;
    rgame_font_destroy(ref->font); /* NULL-safe */
    xfree(ref);
}

static size_t font_ref_size(const void *ptr) {
    (void)ptr;
    return sizeof(rgame_font_ref);
}

static const rb_data_type_t font_data_type = {
    .wrap_struct_name = "rgame_font",
    .function = {
        .dmark = font_ref_mark,
        .dfree = font_ref_free,
        .dsize = font_ref_size,
    },
    .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

static VALUE cFont;

static rgame_font_ref *font_unwrap(VALUE self) {
    rgame_font_ref *ref;
    TypedData_Get_Struct(self, rgame_font_ref, &font_data_type, ref);
    if (!ref->font) {
        rb_raise(rb_eRuntimeError, "font is not initialized");
    }
    return ref;
}

rgame_font *rgame_font_unwrap(VALUE font) {
    return font_unwrap(font)->font;
}

static VALUE font_alloc(VALUE klass) {
    rgame_font_ref *ref;
    VALUE object = TypedData_Make_Struct(klass, rgame_font_ref, &font_data_type, ref);
    ref->font = NULL;
    ref->app_object = Qnil;
    ref->typeface = Qnil;
    return object;
}

/* Font.new(app, typeface) — opens a face from the typeface's own bytes, at its
 * size. */
static VALUE font_initialize(VALUE self, VALUE app, VALUE typeface) {
    rgame_font_ref *ref;
    TypedData_Get_Struct(self, rgame_font_ref, &font_data_type, ref);
    if (ref->font) {
        rb_raise(rb_eRuntimeError, "font is already initialized");
    }

    rgame_app *engine_app = rgame_app_unwrap(app); /* raises TypeError otherwise */
    VALUE typeface_class = rb_path2class("RGame::Util::Typeface");
    if (!rb_obj_is_kind_of(typeface, typeface_class)) {
        rb_raise(rb_eTypeError, "a font is built from a %" PRIsVALUE ", got %" PRIsVALUE,
                 typeface_class, rb_inspect(typeface));
    }

    VALUE bytes = rb_funcall(typeface, rb_intern("bytes"), 0);
    StringValue(bytes);
    int height = NUM2INT(rb_funcall(typeface, rb_intern("height"), 0));

    char error[256] = {0};
    rgame_font *font = rgame_font_open(engine_app, (const unsigned char *)RSTRING_PTR(bytes),
                                       (size_t)RSTRING_LEN(bytes), height, error, sizeof(error));
    RB_GC_GUARD(bytes);
    if (!font) {
        rb_raise(rb_const_get(cFont, rb_intern("LoadError")), "%s", error);
    }

    ref->font = font;
    ref->app_object = app;
    ref->typeface = typeface;
    return self;
}

/* The RGame::Util::Typeface this font was built from. */
static VALUE font_typeface(VALUE self) {
    return font_unwrap(self)->typeface;
}

/* The size it was loaded at, and the amount to step by for a second line. */
static VALUE font_height(VALUE self) {
    return INT2NUM(rgame_font_height(font_unwrap(self)->font));
}

/*
 * #text_width(string) — what #text would occupy, in pixels.
 *
 * Deliberately usable outside `draw`: measuring touches no GL, and laying out a
 * menu happens while updating, not while drawing.
 */
static VALUE font_text_width(VALUE self, VALUE string) {
    rgame_font_ref *ref = font_unwrap(self);

    /* Raises TypeError rather than letting RSTRING_PTR read a non-String's
     * innards as a char*, which segfaults. See renderer_ext.c's #draw_text. */
    StringValue(string);

    /* The bytes as Ruby holds them. No copy, no per-call allocation, and the
     * codepoint walk happens in C where it costs nothing. */
    const char *text = RSTRING_PTR(string);
    long length = RSTRING_LEN(string);
    double width = rgame_font_measure(ref->font, text, (size_t)length);

    /* Keeps `string` alive across the call above, which matters because
     * RSTRING_PTR hands out a pointer the GC does not know we are holding. */
    RB_GC_GUARD(string);
    return DBL2NUM(width);
}

/* How many atlas pages exist across every live font. Test-only, and named so:
 * a leaked page is invisible — nothing looks wrong until video memory runs
 * out. The image side has the same counter for the same reason. */
static VALUE font_s_debug_live_pages(VALUE klass) {
    (void)klass;
    return LONG2NUM(rgame_font_live_pages());
}

static VALUE font_inspect(VALUE self) {
    rgame_font_ref *ref;
    TypedData_Get_Struct(self, rgame_font_ref, &font_data_type, ref);
    if (!ref->font) {
        return rb_sprintf("#<%" PRIsVALUE " (uninitialized)>", rb_obj_class(self));
    }

    return rb_sprintf("#<%" PRIsVALUE " %dpx>", rb_obj_class(self),
                      rgame_font_height(ref->font));
}

void rgame_init_font(VALUE mCore) {
    cFont = rb_define_class_under(mCore, "Font", rb_cObject);

    /* Raised when a file cannot be read or is not a TrueType font — an everyday
     * condition, so it gets a name a game can rescue. */
    rb_define_class_under(cFont, "LoadError", rb_eStandardError);

    rb_define_alloc_func(cFont, font_alloc);
    rb_define_method(cFont, "initialize", font_initialize, 2);
    rb_define_method(cFont, "typeface", font_typeface, 0);
    rb_define_method(cFont, "height", font_height, 0);
    rb_define_method(cFont, "text_width", font_text_width, 1);
    rb_define_method(cFont, "inspect", font_inspect, 0);
    rb_define_singleton_method(cFont, "debug_live_pages", font_s_debug_live_pages, 0);
}
