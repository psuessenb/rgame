/*
 * renderer_ext.c — the Ruby binding for RGame::Core::Renderer's primitives.
 *
 * This is the low half of the renderer. Every method here is a thin call into
 * the engine's drawing API, taking plain numbers and a packed colour; the
 * pleasant half — keyword arguments, default z values, colour coercion and the
 * `rotated { }` block forms — is pure Ruby in lib/rgame/core/renderer.rb,
 * which reopens this class.
 *
 * The split is deliberate. Keyword parsing and colour handling in C would be a
 * lot of rb_get_kwargs for no gain, while the arithmetic behind a circle or a
 * thick line genuinely belongs in C (primitives.c) where it is Check-tested.
 * So C draws, and Ruby makes it comfortable.
 *
 * ---------------------------------------------------------------------------
 * Why a renderer object at all, rather than methods on App
 * ---------------------------------------------------------------------------
 *
 * The engine layer (RGame::Engine) may not name RGame::Core. It receives a
 * renderer in `draw` and calls methods on it that it knows only by name — so
 * "the thing you draw with" has to be a separate object that a spec can
 * substitute with a recording fake. An App with draw methods on it could not be
 * faked without faking the window too.
 */

#include "ruby/core_ext.h"

#include "rgame/core.h"

typedef struct {
    rgame_app *app;
    VALUE app_object; /* marked: the window must outlive anything drawing into it */
    /*
     * While a recording is open, every Image drawn is collected here and handed
     * to the finished Recording, which then keeps them alive. A baked batch
     * holds a GL texture *number*, so an Image collected out from under it
     * would leave the recording drawing whatever the driver put there next.
     * Qnil when not recording.
     */
    VALUE recorded_images;
} rgame_renderer_ref;

static void renderer_mark(void *ptr) {
    rgame_renderer_ref *ref = ptr;
    rb_gc_mark(ref->app_object);
    rb_gc_mark(ref->recorded_images);
}

static size_t renderer_size(const void *ptr) {
    (void)ptr;
    return sizeof(rgame_renderer_ref);
}

static const rb_data_type_t renderer_data_type = {
    .wrap_struct_name = "rgame_renderer",
    .function = {
        .dmark = renderer_mark,
        .dfree = RUBY_TYPED_DEFAULT_FREE, /* the app is not ours to free */
        .dsize = renderer_size,
    },
    .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

static VALUE cRenderer;

/*
 * The app to draw into, or an exception.
 *
 * Drawing outside `draw` is refused rather than ignored. The canvas would
 * accept the vertices and drop them at the next frame's begin, so the failure
 * would otherwise be an invisible one: no error, no output, nothing to search
 * for. This is the same reasoning as the engine bracketing the frame itself —
 * the mistake that cannot be made silently is the one worth designing for.
 */
static rgame_app *drawing_app(VALUE self) {
    rgame_renderer_ref *ref;
    TypedData_Get_Struct(self, rgame_renderer_ref, &renderer_data_type, ref);
    if (!ref->app) {
        rb_raise(rb_eRuntimeError, "renderer is not initialized");
    }
    if (!rgame_app_is_drawing(ref->app)) {
        rb_raise(rb_eRuntimeError,
                 "drawing is only allowed inside #draw (the frame is not open)");
    }
    return ref->app;
}

static VALUE renderer_alloc(VALUE klass) {
    rgame_renderer_ref *ref;
    VALUE object = TypedData_Make_Struct(klass, rgame_renderer_ref, &renderer_data_type, ref);
    ref->app = NULL;
    ref->app_object = Qnil;
    ref->recorded_images = Qnil;
    return object;
}

/* Renderer.new(app) */
static VALUE renderer_initialize(VALUE self, VALUE app) {
    rgame_renderer_ref *ref;
    TypedData_Get_Struct(self, rgame_renderer_ref, &renderer_data_type, ref);

    ref->app = rgame_app_unwrap(app); /* raises TypeError on anything else */
    ref->app_object = app;
    ref->recorded_images = Qnil;
    return self;
}

/*
 * The App this renderer draws into.
 *
 * Exposed because the Ruby half builds the default font lazily and needs an app
 * to build it from — see lib/rgame/core/renderer.rb. A renderer already holds
 * the app reachable, so handing it back adds no lifetime question.
 */
static VALUE renderer_app(VALUE self) {
    rgame_renderer_ref *ref;
    TypedData_Get_Struct(self, rgame_renderer_ref, &renderer_data_type, ref);
    return ref->app_object;
}

/* True while a frame is open — that is, inside the app's #draw. */
static VALUE renderer_drawing_p(VALUE self) {
    rgame_renderer_ref *ref;
    TypedData_Get_Struct(self, rgame_renderer_ref, &renderer_data_type, ref);
    return ref->app && rgame_app_is_drawing(ref->app) ? Qtrue : Qfalse;
}

/* Colours arrive already packed as 0xRRGGBBAA — see RGame::Util::Color#packed.
 * NUM2UINT would reject the high bit on some widths, so go via unsigned long. */
static unsigned int packed_color(VALUE color) {
    return (unsigned int)(NUM2ULONG(color) & 0xFFFFFFFFul);
}

static VALUE renderer_draw_rect(VALUE self, VALUE x, VALUE y, VALUE width, VALUE height,
                                VALUE z, VALUE color) {
    rgame_app_draw_rect(drawing_app(self), (float)NUM2DBL(x), (float)NUM2DBL(y),
                        (float)NUM2DBL(width), (float)NUM2DBL(height), packed_color(color),
                        NUM2DBL(z));
    return self;
}

static VALUE renderer_draw_quad(int argc, VALUE *argv, VALUE self) {
    /* Ten positional arguments is past the point where naming each parameter
     * helps, so this one takes an argv and unpacks it in a loop. */
    rb_check_arity(argc, 10, 10);

    float xy8[8];
    for (int i = 0; i < 8; i++) {
        xy8[i] = (float)NUM2DBL(argv[i]);
    }
    rgame_app_draw_quad(drawing_app(self), xy8, packed_color(argv[9]), NUM2DBL(argv[8]));
    return self;
}

static VALUE renderer_draw_triangle(int argc, VALUE *argv, VALUE self) {
    rb_check_arity(argc, 8, 8);

    float xy6[6];
    for (int i = 0; i < 6; i++) {
        xy6[i] = (float)NUM2DBL(argv[i]);
    }
    rgame_app_draw_triangle(drawing_app(self), xy6, packed_color(argv[7]), NUM2DBL(argv[6]));
    return self;
}

static VALUE renderer_draw_line(int argc, VALUE *argv, VALUE self) {
    rb_check_arity(argc, 7, 7);

    rgame_app_draw_line(drawing_app(self), (float)NUM2DBL(argv[0]), (float)NUM2DBL(argv[1]),
                        (float)NUM2DBL(argv[2]), (float)NUM2DBL(argv[3]),
                        (float)NUM2DBL(argv[4]), packed_color(argv[6]), NUM2DBL(argv[5]));
    return self;
}

static VALUE renderer_draw_circle(int argc, VALUE *argv, VALUE self) {
    rb_check_arity(argc, 6, 6);

    rgame_app_draw_circle(drawing_app(self), (float)NUM2DBL(argv[0]), (float)NUM2DBL(argv[1]),
                          (float)NUM2DBL(argv[2]), NUM2INT(argv[3]), packed_color(argv[5]),
                          NUM2DBL(argv[4]));
    return self;
}

/* An image or font drawn through the wrong app's renderer samples nothing and
 * paints white quads — silently. Every such call reports the mismatch so it can
 * be an error instead of a mystery on screen. */
static void check_drawn(int drawn, VALUE subject) {
    if (!drawn) {
        rb_raise(rb_eArgError,
                 "%" PRIsVALUE " belongs to a different App than this renderer; "
                 "a texture cannot be drawn into another window's GL context",
                 subject);
    }
}

/* If a recording is open, remember the image so the finished Recording can keep
 * its texture alive. Cheap and only while recording — a bake happens once. */
static void note_recorded_image(VALUE self, VALUE image) {
    rgame_renderer_ref *ref;
    TypedData_Get_Struct(self, rgame_renderer_ref, &renderer_data_type, ref);
    if (!NIL_P(ref->recorded_images)) {
        rb_ary_push(ref->recorded_images, image);
    }
}

static VALUE renderer_draw_image(VALUE self, VALUE image, VALUE x, VALUE y, VALUE z,
                                 VALUE color) {
    check_drawn(rgame_app_draw_image(drawing_app(self), rgame_image_unwrap(image),
                                     (float)NUM2DBL(x), (float)NUM2DBL(y), packed_color(color),
                                     NUM2DBL(z)),
                image);
    note_recorded_image(self, image);
    return self;
}

/* (image, x, y, scale_x, scale_y, z, color) — seven arguments, so -1 arity and
 * an explicit check rather than seven named parameters. */
static VALUE renderer_draw_image_scaled(int argc, VALUE *argv, VALUE self) {
    rb_check_arity(argc, 7, 7);

    check_drawn(rgame_app_draw_image_scaled(drawing_app(self), rgame_image_unwrap(argv[0]),
                                            (float)NUM2DBL(argv[1]), (float)NUM2DBL(argv[2]),
                                            (float)NUM2DBL(argv[3]), (float)NUM2DBL(argv[4]),
                                            packed_color(argv[6]), NUM2DBL(argv[5])),
                argv[0]);
    note_recorded_image(self, argv[0]);
    return self;
}

static VALUE renderer_draw_image_rot(int argc, VALUE *argv, VALUE self) {
    rb_check_arity(argc, 7, 7);

    check_drawn(rgame_app_draw_image_rot(drawing_app(self), rgame_image_unwrap(argv[0]),
                                         (float)NUM2DBL(argv[1]), (float)NUM2DBL(argv[2]),
                                         (float)NUM2DBL(argv[3]), (float)NUM2DBL(argv[4]),
                                         packed_color(argv[6]), NUM2DBL(argv[5])),
                argv[0]);
    note_recorded_image(self, argv[0]);
    return self;
}

/*
 * #draw_text(font, string, x, y, z, rgba)
 *
 * The string's bytes go to C as they are: no `each_char`, no codepoints array,
 * nothing allocated per call. Walking UTF-8 is what font.c is for.
 */
static VALUE renderer_draw_text(int argc, VALUE *argv, VALUE self) {
    rb_check_arity(argc, 6, 6);

    VALUE font = argv[0];
    VALUE string = argv[1];
    const char *text = RSTRING_PTR(string);
    long length = RSTRING_LEN(string);

    int drawn = rgame_app_draw_text(drawing_app(self), rgame_font_unwrap(font), text,
                                    (size_t)length, (float)NUM2DBL(argv[2]),
                                    (float)NUM2DBL(argv[3]), packed_color(argv[5]),
                                    NUM2DBL(argv[4]));
    /* RSTRING_PTR hands out a pointer the collector does not know about. */
    RB_GC_GUARD(string);

    check_drawn(drawn, font);
    return self;
}

static VALUE renderer_push_translate(VALUE self, VALUE dx, VALUE dy) {
    rgame_app_push_translate(drawing_app(self), (float)NUM2DBL(dx), (float)NUM2DBL(dy));
    return self;
}

static VALUE renderer_push_rotate(VALUE self, VALUE degrees, VALUE pivot_x, VALUE pivot_y) {
    rgame_app_push_rotate(drawing_app(self), (float)NUM2DBL(degrees), (float)NUM2DBL(pivot_x),
                          (float)NUM2DBL(pivot_y));
    return self;
}

static VALUE renderer_push_scale(VALUE self, VALUE sx, VALUE sy) {
    rgame_app_push_scale(drawing_app(self), (float)NUM2DBL(sx), (float)NUM2DBL(sy));
    return self;
}

static VALUE renderer_push_clip(VALUE self, VALUE x, VALUE y, VALUE width, VALUE height) {
    if (!rgame_app_push_clip(drawing_app(self), NUM2INT(x), NUM2INT(y), NUM2INT(width),
                             NUM2INT(height))) {
        /* Clipping cannot be baked into a recording; see core.h. Saying so
         * beats recording geometry that quietly ignores the clip. */
        rb_raise(rb_eRuntimeError,
                 "a clip cannot be recorded — wrap the replay in #clipped instead");
    }
    return self;
}

/* ------------------------------------------------------------------------- *
 * Recording
 *
 * Three primitives rather than one block-taking method: Renderer#record in
 * lib/rgame/core/renderer.rb wraps them in begin/ensure, which is where a
 * `raise` mid-bake gets unwound. Doing that in C would mean rb_protect for no
 * benefit.
 * ------------------------------------------------------------------------- */

static VALUE renderer_begin_record(VALUE self) {
    rgame_renderer_ref *ref;
    TypedData_Get_Struct(self, rgame_renderer_ref, &renderer_data_type, ref);

    if (!rgame_app_begin_record(drawing_app(self))) {
        rb_raise(rb_eRuntimeError, "already recording (recordings do not nest)");
    }
    ref->recorded_images = rb_ary_new();
    return self;
}

static VALUE renderer_end_record(VALUE self) {
    rgame_renderer_ref *ref;
    TypedData_Get_Struct(self, rgame_renderer_ref, &renderer_data_type, ref);

    VALUE images = ref->recorded_images;
    ref->recorded_images = Qnil;

    rgame_recording *recording = rgame_app_end_record(ref->app);
    if (!recording) {
        rb_raise(rb_eRuntimeError, "no recording is open");
    }

    return rgame_recording_wrap(recording, ref->app_object, ref->app, images);
}

static VALUE renderer_cancel_record(VALUE self) {
    rgame_renderer_ref *ref;
    TypedData_Get_Struct(self, rgame_renderer_ref, &renderer_data_type, ref);

    ref->recorded_images = Qnil;
    rgame_app_cancel_record(ref->app);
    return self;
}

static VALUE renderer_pop(VALUE self) {
    rgame_app_pop(drawing_app(self));
    return self;
}

void rgame_init_renderer(VALUE mCore) {
    cRenderer = rb_define_class_under(mCore, "Renderer", rb_cObject);

    rb_define_alloc_func(cRenderer, renderer_alloc);
    rb_define_method(cRenderer, "initialize", renderer_initialize, 1);
    rb_define_method(cRenderer, "drawing?", renderer_drawing_p, 0);
    rb_define_method(cRenderer, "app", renderer_app, 0);

    rb_define_method(cRenderer, "draw_rect", renderer_draw_rect, 6);
    rb_define_method(cRenderer, "draw_quad", renderer_draw_quad, -1);
    rb_define_method(cRenderer, "draw_triangle", renderer_draw_triangle, -1);
    rb_define_method(cRenderer, "draw_line", renderer_draw_line, -1);
    rb_define_method(cRenderer, "draw_circle", renderer_draw_circle, -1);
    rb_define_method(cRenderer, "draw_image", renderer_draw_image, 5);
    rb_define_method(cRenderer, "draw_image_scaled", renderer_draw_image_scaled, -1);
    rb_define_method(cRenderer, "draw_image_rot", renderer_draw_image_rot, -1);
    rb_define_method(cRenderer, "draw_text", renderer_draw_text, -1);

    rb_define_method(cRenderer, "push_translate", renderer_push_translate, 2);
    rb_define_method(cRenderer, "push_rotate", renderer_push_rotate, 3);
    rb_define_method(cRenderer, "push_scale", renderer_push_scale, 2);
    rb_define_method(cRenderer, "push_clip", renderer_push_clip, 4);
    rb_define_method(cRenderer, "pop", renderer_pop, 0);

    rb_define_method(cRenderer, "begin_record", renderer_begin_record, 0);
    rb_define_method(cRenderer, "end_record", renderer_end_record, 0);
    rb_define_method(cRenderer, "cancel_record", renderer_cancel_record, 0);
}
