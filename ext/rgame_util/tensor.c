/*
 * tensor.c — RGame::Util::Tensor, a C-backed re-implementation of what used to
 * live in lib/rgame/util/tensor.rb.
 *
 * A fixed-size 3-D grid backed by a single flat C array, addressed as [x, y, z].
 * Layout is x-fastest then y then z, so one z-slice ([*, *, z]) is a contiguous
 * run — same layout the Ruby version documented.
 *
 * This is a *pure data* extension: it includes only <ruby.h>, never SDL/GL, so
 * requiring it costs nothing but the Ruby object machinery. It is a separate
 * .so from the SDL-linked engine extension for exactly that reason.
 *
 * The one genuinely C-extension-specific concern here is the garbage collector.
 * Each cell holds an arbitrary Ruby object (nil, an Integer, a Symbol, ...). If
 * we stash those VALUEs in a plain C array, the GC has no idea they're reachable
 * and will happily collect them out from under us. TypedData lets us register a
 * `mark` function so the GC walks our array and keeps every stored value alive.
 */

#include "util_ext.h"

/*
 * The C struct each RGame::Util::Tensor Ruby object wraps. `data` is a flat
 * array of `size` VALUEs (size == plane * depth, plane == width * height).
 * Dimensions are `long` to match Ruby's integer width and NUM2LONG.
 */
typedef struct {
    long width;
    long height;
    long depth;
    long plane; /* width * height — cached, one z-slice's worth of cells */
    long size;  /* plane * depth — total cell count / length of `data` */
    VALUE *data;
} rgame_tensor;

/*
 * GC mark: tell the collector every Ruby object we're holding is still alive.
 * Called during GC while this Tensor is reachable. rb_gc_mark_locations marks a
 * contiguous [start, end) range of VALUEs in one call, which is exactly our
 * layout. Guard against data == NULL for a half-initialized object (allocated
 * but #initialize not yet run / failed).
 */
static void tensor_mark(void *ptr) {
    rgame_tensor *t = ptr;
    if (t->data) {
        rb_gc_mark_locations(t->data, t->data + t->size);
    }
}

/* Free the backing array and the struct itself when the Tensor is collected. */
static void tensor_free(void *ptr) {
    rgame_tensor *t = ptr;
    xfree(t->data); /* xfree(NULL) is safe */
    xfree(t);
}

/* Report how much memory we own, for ObjectSpace / GC accounting. */
static size_t tensor_memsize(const void *ptr) {
    const rgame_tensor *t = ptr;
    return sizeof(rgame_tensor) + (t->data ? (size_t)t->size * sizeof(VALUE) : 0);
}

static const rb_data_type_t tensor_data_type = {
    .wrap_struct_name = "RGame::Util::Tensor",
    .function = {
        .dmark = tensor_mark,
        .dfree = tensor_free,
        .dsize = tensor_memsize,
    },
    .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

/* Pull the C struct back out of a Tensor Ruby object. */
static rgame_tensor *tensor_unwrap(VALUE self) {
    rgame_tensor *t;
    TypedData_Get_Struct(self, rgame_tensor, &tensor_data_type, t);
    return t;
}

/*
 * alloc: make the wrapper object with a zero-filled struct (TypedData_Make_Struct
 * zeroes it), so data == NULL until #initialize allocates it. Splitting alloc
 * from initialize is the standard Ruby way and means a failure mid-initialize
 * still leaves a valid, freeable object.
 */
static VALUE tensor_alloc(VALUE klass) {
    rgame_tensor *t;
    return TypedData_Make_Struct(klass, rgame_tensor, &tensor_data_type, t);
}

/*
 * RGame::Util::Tensor.new(width, height, depth, initial: nil)
 *
 * rb_scan_args "30:" = 3 required positional args plus a trailing keyword/options
 * hash (the ":"). We read :initial out of that hash; an absent key yields nil via
 * rb_hash_aref, which matches the Ruby default of `initial: nil`.
 */
static VALUE tensor_initialize(int argc, VALUE *argv, VALUE self) {
    VALUE width, height, depth, opts;
    rb_scan_args(argc, argv, "30:", &width, &height, &depth, &opts);

    long w = NUM2LONG(width);
    long h = NUM2LONG(height);
    long d = NUM2LONG(depth);
    if (w < 0 || h < 0 || d < 0) {
        rb_raise(rb_eArgError, "tensor dimensions must be non-negative");
    }

    VALUE initial = Qnil;
    if (!NIL_P(opts)) {
        initial = rb_hash_aref(opts, ID2SYM(rb_intern("initial")));
    }

    rgame_tensor *t = tensor_unwrap(self);
    t->width = w;
    t->height = h;
    t->depth = d;
    t->plane = w * h;
    t->size = t->plane * d;
    t->data = ALLOC_N(VALUE, t->size); /* ALLOC_N(_, 0) returns a valid pointer */
    for (long i = 0; i < t->size; i++) {
        t->data[i] = initial;
    }

    return self;
}

/*
 * Flat index for [x, y, z], with bounds checking. The Ruby version leaned on
 * Array#[] semantics (nil past the end, negative-index wrap); on a raw C array
 * those would be out-of-bounds reads, so instead we range-check every coordinate
 * and raise IndexError — a clean, safe contract for a fixed-size grid.
 */
static long tensor_offset(rgame_tensor *t, VALUE x, VALUE y, VALUE z) {
    long xi = NUM2LONG(x);
    long yi = NUM2LONG(y);
    long zi = NUM2LONG(z);
    if (xi < 0 || xi >= t->width ||
        yi < 0 || yi >= t->height ||
        zi < 0 || zi >= t->depth) {
        rb_raise(rb_eIndexError,
                 "index (%ld, %ld, %ld) out of bounds for tensor "
                 "(%ld, %ld, %ld)",
                 xi, yi, zi, t->width, t->height, t->depth);
    }
    return (zi * t->plane) + (yi * t->width) + xi;
}

static VALUE tensor_aref(VALUE self, VALUE x, VALUE y, VALUE z) {
    rgame_tensor *t = tensor_unwrap(self);
    return t->data[tensor_offset(t, x, y, z)];
}

static VALUE tensor_aset(VALUE self, VALUE x, VALUE y, VALUE z, VALUE value) {
    rgame_tensor *t = tensor_unwrap(self);
    t->data[tensor_offset(t, x, y, z)] = value;
    return value; /* Ruby returns the assigned value from []= regardless */
}

static VALUE tensor_width(VALUE self) {
    return LONG2NUM(tensor_unwrap(self)->width);
}

static VALUE tensor_height(VALUE self) {
    return LONG2NUM(tensor_unwrap(self)->height);
}

static VALUE tensor_depth(VALUE self) {
    return LONG2NUM(tensor_unwrap(self)->depth);
}

/*
 * Class init, called by Init_util_ext in util_ext.c. Splitting the entry point
 * out means adding another Util class does not mean editing this file.
 */
void rgame_init_tensor(VALUE mUtil) {
    VALUE cTensor = rb_define_class_under(mUtil, "Tensor", rb_cObject);

    rb_define_alloc_func(cTensor, tensor_alloc);
    rb_define_method(cTensor, "initialize", tensor_initialize, -1);
    rb_define_method(cTensor, "[]", tensor_aref, 3);
    rb_define_method(cTensor, "[]=", tensor_aset, 4);
    rb_define_method(cTensor, "width", tensor_width, 0);
    rb_define_method(cTensor, "height", tensor_height, 0);
    rb_define_method(cTensor, "depth", tensor_depth, 0);
}
