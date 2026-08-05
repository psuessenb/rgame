/*
 * font_ext.c — the Ruby binding for RGame::Core::Font.
 *
 *   font = RGame::Core::Font.new(app, 18)                        # the shipped font
 *   font = RGame::Core::Font.new(app, 18, path: 'assets/x.ttf')
 *   font.height        # => 18
 *   font.text_width('Score: 1200')
 *
 * The atlas, the cache and the metrics are in font_atlas.c, font.c, atlas.c and
 * glyph_cache.c — three of those four are pure and Check-tested. This file is
 * the wrapper: argument checking, turning a NULL return into an exception that
 * says why, and keeping the app reachable for as long as the font is.
 *
 * The default path is *not* here. It is a packaging question — where a gem
 * installs its data — so lib/rgame/core/font.rb owns it and passes a path down.
 * The C layer has no opinion about where fonts live and no font-name lookup;
 * see docs/plans/gosu-replacement/README.md on why the engine ships a font
 * rather than asking the operating system for one.
 */

#include "ruby/core_ext.h"

#include "text/font_internal.h"
#include "rgame/core.h"

typedef struct {
    rgame_font *font;
    VALUE app_object; /* marked: the atlas pages live in this window's context */
} rgame_font_ref;

static void font_ref_mark(void *ptr) {
    rgame_font_ref *ref = ptr;
    rb_gc_mark(ref->app_object);
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
    return object;
}

/* Font.new(app, pixel_height, path) — the path is supplied by the Ruby half,
 * which defaults it to the shipped font. */
static VALUE font_initialize(VALUE self, VALUE app, VALUE pixel_height, VALUE path) {
    rgame_font_ref *ref;
    TypedData_Get_Struct(self, rgame_font_ref, &font_data_type, ref);

    rgame_app *engine_app = rgame_app_unwrap(app); /* raises TypeError otherwise */
    const char *path_str = StringValueCStr(path);
    int height = NUM2INT(pixel_height);

    char error[256] = {0};
    rgame_font *font = rgame_font_load(engine_app, path_str, height, error, sizeof(error));
    if (!font) {
        rb_raise(rb_const_get(cFont, rb_intern("LoadError")), "%s", error);
    }

    ref->font = font;
    ref->app_object = app;
    return self;
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
    rb_define_method(cFont, "initialize", font_initialize, 3);
    rb_define_method(cFont, "height", font_height, 0);
    rb_define_method(cFont, "text_width", font_text_width, 1);
    rb_define_method(cFont, "inspect", font_inspect, 0);
    rb_define_singleton_method(cFont, "debug_live_pages", font_s_debug_live_pages, 0);
}
