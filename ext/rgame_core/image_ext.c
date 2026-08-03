/*
 * image_ext.c — the Ruby binding for RGame::Core::Image.
 *
 * The decode and upload are in image.c; the rectangle arithmetic behind
 * subimages and tiles is in texture.c and is Check-tested with no GPU. This
 * file is only the wrapper: argument checking, turning C's "returned NULL"
 * into a Ruby exception that says why, and keeping the app object reachable
 * for as long as any image made from it is.
 *
 *   img   = RGame::Core::Image.new(app, 'hero.png')
 *   img.width; img.height
 *   sub   = img.subimage(0, 0, 16, 16)
 *   tiles = RGame::Core::Image.load_tiles(app, 'sheet.png', 16, 16)
 *
 * Slicing never re-decodes: every image above shares one GPU texture, and the
 * texture goes when the last of them does.
 */

#include "core_ext.h"

#include "rgame/core.h"
#include "texture.h"

/*
 * The Ruby object's payload. Two members, and the second is the interesting
 * one: `app` is the Ruby App object this image was loaded from, marked so the
 * collector treats the app as reachable from every image.
 *
 * That is a deliberate ownership statement, not just GC hygiene. An image is
 * meaningless without the context its pixels live in, and a game that keeps a
 * sprite around has, by definition, not finished with the window. (The C layer
 * survives the other order too — see rgame_app_gl_retain — but a Ruby user
 * should never be in a position to observe it.)
 */
typedef struct {
    rgame_image *image;
    VALUE app;
} rgame_image_ref;

static void image_ref_mark(void *ptr) {
    rgame_image_ref *ref = ptr;
    rb_gc_mark(ref->app);
}

static void image_ref_free(void *ptr) {
    rgame_image_ref *ref = ptr;
    rgame_image_destroy(ref->image); /* NULL-safe */
    xfree(ref);
}

static size_t image_ref_size(const void *ptr) {
    (void)ptr;
    return sizeof(rgame_image_ref);
}

static const rb_data_type_t image_data_type = {
    .wrap_struct_name = "rgame_image",
    .function = {
        .dmark = image_ref_mark,
        .dfree = image_ref_free,
        .dsize = image_ref_size,
    },
    .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

static VALUE cImage;

static rgame_image_ref *image_ref_unwrap(VALUE self) {
    rgame_image_ref *ref;
    TypedData_Get_Struct(self, rgame_image_ref, &image_data_type, ref);
    if (!ref->image) {
        rb_raise(rb_eRuntimeError, "image is not initialized");
    }
    return ref;
}

/* The accessor other files in this extension use (see core_ext.h) — the
 * renderer needs the C handle to draw. TypedData_Get_Struct raises TypeError on
 * anything that is not an Image, so the type check comes for free. */
rgame_image *rgame_image_unwrap(VALUE image) {
    return image_ref_unwrap(image)->image;
}

/*
 * Wraps a C handle in a fresh Ruby object. Takes ownership: if allocating the
 * Ruby side raises, the handle would leak, so the payload is filled in before
 * anything else can fail.
 */
static VALUE image_wrap(rgame_image *image, VALUE app) {
    rgame_image_ref *ref;
    VALUE object = TypedData_Make_Struct(cImage, rgame_image_ref, &image_data_type, ref);
    ref->image = image;
    ref->app = app;
    return object;
}

/*
 * Image.new(app, path)
 *
 * `app` comes first and is required, rather than being implied by "the window
 * that happens to be open". Textures belong to one GL context, so an image
 * genuinely is an image *of* an app — and saying so is what lets the object
 * hold the app reachable, and what makes two windows work at all.
 */
static VALUE image_initialize(VALUE self, VALUE app, VALUE path) {
    rgame_image_ref *ref;
    TypedData_Get_Struct(self, rgame_image_ref, &image_data_type, ref);

    /* Unwrapping raises TypeError on anything that is not an App, so there is
     * no separate type check to keep in step with this one. */
    rgame_app *engine_app = rgame_app_unwrap(app);
    const char *path_str = StringValueCStr(path);

    char error[256] = {0};
    rgame_image *image = rgame_image_load(engine_app, path_str, error, sizeof(error));
    if (!image) {
        rb_raise(rb_const_get(cImage, rb_intern("LoadError")), "%s", error);
    }

    ref->image = image;
    ref->app = app;
    return self;
}

static VALUE image_alloc(VALUE klass) {
    rgame_image_ref *ref;
    VALUE object = TypedData_Make_Struct(klass, rgame_image_ref, &image_data_type, ref);
    ref->image = NULL;
    ref->app = Qnil;
    return object;
}

static VALUE image_width(VALUE self) {
    return INT2NUM(rgame_image_width(image_ref_unwrap(self)->image));
}

static VALUE image_height(VALUE self) {
    return INT2NUM(rgame_image_height(image_ref_unwrap(self)->image));
}

/*
 * #subimage(x, y, width, height)
 *
 * Raises rather than returning nil on a rect that does not fit. A nil here
 * would travel a long way — into an asset table, out of it three scenes
 * later — before failing as a NoMethodError with nothing left pointing at the
 * bad coordinates.
 */
static VALUE image_subimage(VALUE self, VALUE x, VALUE y, VALUE width, VALUE height) {
    rgame_image_ref *ref = image_ref_unwrap(self);

    rgame_image *sub = rgame_image_subimage(ref->image, NUM2INT(x), NUM2INT(y), NUM2INT(width),
                                            NUM2INT(height));
    if (!sub) {
        rb_raise(rb_eArgError,
                 "subimage %" PRIsVALUE ",%" PRIsVALUE " %" PRIsVALUE "x%" PRIsVALUE
                 " does not fit in a %dx%d image",
                 x, y, width, height, rgame_image_width(ref->image),
                 rgame_image_height(ref->image));
    }

    return image_wrap(sub, ref->app);
}

/* #tile_count(tile_width, tile_height) — whole tiles only. */
static VALUE image_tile_count(VALUE self, VALUE tile_width, VALUE tile_height) {
    return INT2NUM(rgame_image_tile_count(image_ref_unwrap(self)->image, NUM2INT(tile_width),
                                          NUM2INT(tile_height)));
}

/* #tile(tile_width, tile_height, index) — row-major, left to right then down. */
static VALUE image_tile(VALUE self, VALUE tile_width, VALUE tile_height, VALUE index) {
    rgame_image_ref *ref = image_ref_unwrap(self);

    rgame_image *tile = rgame_image_tile(ref->image, NUM2INT(tile_width), NUM2INT(tile_height),
                                         NUM2INT(index));
    if (!tile) {
        rb_raise(rb_eIndexError, "tile %" PRIsVALUE " is out of range (%d tiles of %" PRIsVALUE
                                 "x%" PRIsVALUE ")",
                 index,
                 rgame_image_tile_count(ref->image, NUM2INT(tile_width), NUM2INT(tile_height)),
                 tile_width, tile_height);
    }

    return image_wrap(tile, ref->app);
}

static VALUE image_inspect(VALUE self) {
    rgame_image_ref *ref;
    TypedData_Get_Struct(self, rgame_image_ref, &image_data_type, ref);
    if (!ref->image) {
        return rb_sprintf("#<%" PRIsVALUE " (uninitialized)>", rb_obj_class(self));
    }

    return rb_sprintf("#<%" PRIsVALUE " %dx%d>", rb_obj_class(self),
                      rgame_image_width(ref->image), rgame_image_height(ref->image));
}

/*
 * Image.debug_live_textures — how many GPU textures the engine is holding.
 *
 * Test-only, and named so. A leaked texture is silent: nothing is slower and
 * nothing looks wrong until video memory runs out an hour into play. This is
 * what lets a spec assert that dropping a sheet and all its tiles actually
 * releases the upload — including in the case that only a garbage collector
 * can produce, where an app and its images are swept in an arbitrary order.
 */
static VALUE image_s_debug_live_textures(VALUE klass) {
    (void)klass;
    return LONG2NUM(rgame_texture_live_sheets());
}

void rgame_init_image(VALUE mCore) {
    cImage = rb_define_class_under(mCore, "Image", rb_cObject);

    /* Raised when a file cannot be read or decoded — an everyday condition
     * (a typo'd path, a truncated asset), so it gets a name a game can rescue
     * rather than a bare RuntimeError. */
    rb_define_class_under(cImage, "LoadError", rb_eStandardError);

    rb_define_alloc_func(cImage, image_alloc);
    rb_define_method(cImage, "initialize", image_initialize, 2);
    rb_define_method(cImage, "width", image_width, 0);
    rb_define_method(cImage, "height", image_height, 0);
    rb_define_method(cImage, "subimage", image_subimage, 4);
    rb_define_method(cImage, "tile_count", image_tile_count, 2);
    rb_define_method(cImage, "tile", image_tile, 3);
    rb_define_method(cImage, "inspect", image_inspect, 0);
    rb_define_singleton_method(cImage, "debug_live_textures", image_s_debug_live_textures, 0);
}
