/*
 * recording_ext.c — the Ruby binding for RGame::Core::Recording.
 *
 * A recording is made by `RGame::Core::Renderer#record`, never by `new`:
 *
 *     ground = renderer.record { tiles.each { |t| renderer.image(t.image, t.x, t.y) } }
 *     ground.draw(-camera.x, -camera.y)
 *
 * The baking and the replay are in recording.c and canvas.c, both pure. What
 * this file adds is the two things only Ruby can do: hold the images the
 * recording drew, so their GPU textures cannot be freed while a recording still
 * references them, and refuse a replay outside a frame.
 *
 * ---------------------------------------------------------------------------
 * Why the images have to be held
 * ---------------------------------------------------------------------------
 *
 * A baked batch stores a GL texture *name* — a number. If the Image it came
 * from is collected, its texture is deleted and that number now refers to
 * nothing; replaying would draw whatever the driver put there next, or nothing
 * at all, with no error. So the renderer collects the images drawn during a
 * recording, and the recording marks them for as long as it lives. Holding a
 * texture alive while something still draws it is the same rule as everywhere
 * else here; it just has to be spelled out at this layer, because the C side
 * only ever saw a number.
 */

#include "ruby/core_ext.h"

#include "graphics/recording.h"
#include "rgame/core.h"

typedef struct {
    rgame_recording *recording;
    rgame_app *app;
    VALUE app_object; /* marked: the textures live in this window's context */
    VALUE images;     /* marked: an Array of every Image baked into this */
} rgame_recording_ref;

static void recording_mark(void *ptr) {
    rgame_recording_ref *ref = ptr;
    rb_gc_mark(ref->app_object);
    rb_gc_mark(ref->images);
}

static void recording_free(void *ptr) {
    rgame_recording_ref *ref = ptr;
    rgame_recording_free(ref->recording); /* NULL-safe */
    xfree(ref);
}

static size_t recording_size(const void *ptr) {
    (void)ptr;
    return sizeof(rgame_recording_ref);
}

static const rb_data_type_t recording_data_type = {
    .wrap_struct_name = "rgame_recording",
    .function = {
        .dmark = recording_mark,
        .dfree = recording_free,
        .dsize = recording_size,
    },
    .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

static VALUE cRecording;

static rgame_recording_ref *recording_unwrap(VALUE self) {
    rgame_recording_ref *ref;
    TypedData_Get_Struct(self, rgame_recording_ref, &recording_data_type, ref);
    if (!ref->recording) {
        rb_raise(rb_eRuntimeError, "recording is not initialized");
    }
    return ref;
}

/*
 * Declared even though `new` is refused below: wrapping a TypedData payload in
 * a class that still has Object's allocator makes Ruby undefine it for us and
 * warn about it. Saying so up front is one line and keeps the load quiet.
 */
static VALUE recording_alloc(VALUE klass) {
    rgame_recording_ref *ref;
    VALUE object = TypedData_Make_Struct(klass, rgame_recording_ref, &recording_data_type, ref);
    ref->recording = NULL;
    ref->app = NULL;
    ref->app_object = Qnil;
    ref->images = Qnil;
    return object;
}

VALUE rgame_recording_wrap(rgame_recording *recording, VALUE app_object, rgame_app *app,
                           VALUE images) {
    rgame_recording_ref *ref;
    VALUE object = TypedData_Make_Struct(cRecording, rgame_recording_ref, &recording_data_type,
                                         ref);
    ref->recording = recording;
    ref->app = app;
    ref->app_object = app_object;
    ref->images = images;
    return object;
}

/*
 * #draw_at(x, y, z, rgba) — the raw form; RGame::Core::Recording#draw in
 * lib/rgame/core/recording.rb is the one with keywords and colour coercion.
 */
static VALUE recording_draw_at(VALUE self, VALUE x, VALUE y, VALUE z, VALUE color) {
    rgame_recording_ref *ref = recording_unwrap(self);

    /* The app that owns these textures has to be the one mid-frame. Anything
     * else would append to a canvas nobody is about to submit, and draw
     * nothing at all. */
    if (!rgame_app_is_drawing(ref->app)) {
        rb_raise(rb_eRuntimeError,
                 "drawing is only allowed inside #draw (the frame is not open)");
    }

    rgame_app_draw_recording(ref->app, ref->recording, (float)NUM2DBL(x), (float)NUM2DBL(y),
                             (unsigned int)(NUM2ULONG(color) & 0xFFFFFFFFul), NUM2DBL(z));
    return self;
}

/* How many GL calls a replay costs — one per texture. Mostly for tests and for
 * seeing whether a bake did what was hoped. */
static VALUE recording_batch_count(VALUE self) {
    return UINT2NUM(rgame_recording_batch_count(recording_unwrap(self)->recording));
}

static VALUE recording_vertex_count(VALUE self) {
    return UINT2NUM(rgame_recording_vertex_count(recording_unwrap(self)->recording));
}

static VALUE recording_empty_p(VALUE self) {
    return rgame_recording_vertex_count(recording_unwrap(self)->recording) == 0 ? Qtrue : Qfalse;
}

/* The size of what was baked, so a game can skip replaying an off-screen
 * layer. Measured in the recording's own coordinates. */
static VALUE recording_width(VALUE self) {
    float min_x = 0.0f, max_x = 0.0f;
    rgame_recording_bounds(recording_unwrap(self)->recording, &min_x, NULL, &max_x, NULL);
    return DBL2NUM((double)(max_x - min_x));
}

static VALUE recording_height(VALUE self) {
    float min_y = 0.0f, max_y = 0.0f;
    rgame_recording_bounds(recording_unwrap(self)->recording, NULL, &min_y, NULL, &max_y);
    return DBL2NUM((double)(max_y - min_y));
}

static VALUE recording_inspect(VALUE self) {
    rgame_recording_ref *ref;
    TypedData_Get_Struct(self, rgame_recording_ref, &recording_data_type, ref);
    if (!ref->recording) {
        return rb_sprintf("#<%" PRIsVALUE " (uninitialized)>", rb_obj_class(self));
    }

    return rb_sprintf("#<%" PRIsVALUE " %u batches, %u vertices>", rb_obj_class(self),
                      rgame_recording_batch_count(ref->recording),
                      rgame_recording_vertex_count(ref->recording));
}

/* Recordings come out of Renderer#record, so `new` is not part of the API —
 * there is nothing a caller could pass that would make a valid one. */
static VALUE recording_s_new(int argc, VALUE *argv, VALUE klass) {
    (void)argc;
    (void)argv;
    rb_raise(rb_eNoMethodError, "%" PRIsVALUE " is created by Renderer#record, not by .new",
             klass);
}

void rgame_init_recording(VALUE mCore) {
    cRecording = rb_define_class_under(mCore, "Recording", rb_cObject);

    rb_define_alloc_func(cRecording, recording_alloc);
    rb_define_singleton_method(cRecording, "new", recording_s_new, -1);
    rb_define_method(cRecording, "draw_at", recording_draw_at, 4);
    rb_define_method(cRecording, "batch_count", recording_batch_count, 0);
    rb_define_method(cRecording, "vertex_count", recording_vertex_count, 0);
    rb_define_method(cRecording, "empty?", recording_empty_p, 0);
    rb_define_method(cRecording, "width", recording_width, 0);
    rb_define_method(cRecording, "height", recording_height, 0);
    rb_define_method(cRecording, "inspect", recording_inspect, 0);
}
