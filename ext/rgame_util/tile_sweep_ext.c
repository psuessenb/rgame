/*
 * tile_sweep_ext.c — the Ruby binding for RGame::Util::TileSweep.
 *
 * The arithmetic lives in tile_sweep.{c,h}, pure and covered by the Check
 * suite. What this file adds is lifetime and refusals: the C sweep holds a
 * pointer into the SolidGrid it reads, so the Ruby object holds the grid too
 * and marks it; and a coordinate crosses into C through NUM2DBL, so anything
 * but a number is a TypeError.
 *
 * resolve_x and resolve_y run once per axis per frame for every mover blocked
 * by tiles, so they convert and call and nothing else — no allocation, and a
 * Float comes back as an immediate value.
 */

#include "util_ext.h"

#include <math.h>

#include "tile_sweep.h"

typedef struct {
    VALUE grid;
    rgame_tile_sweep sweep;
} tile_sweep_ref;

static long live_sweeps = 0;

static void tile_sweep_mark(void *ptr) {
    tile_sweep_ref *ref = ptr;
    rb_gc_mark(ref->grid);
}

static void tile_sweep_free(void *ptr) {
    xfree(ptr);
    live_sweeps--;
}

static size_t tile_sweep_memsize(const void *ptr) {
    (void)ptr;
    return sizeof(tile_sweep_ref);
}

static const rb_data_type_t tile_sweep_data_type = {
    .wrap_struct_name = "rgame_tile_sweep",
    .function = {
        .dmark = tile_sweep_mark,
        .dfree = tile_sweep_free,
        .dsize = tile_sweep_memsize,
    },
    .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

static tile_sweep_ref *unwrap(VALUE self) {
    tile_sweep_ref *ref;
    TypedData_Get_Struct(self, tile_sweep_ref, &tile_sweep_data_type, ref);
    return ref;
}

static double tile_size(VALUE value, const char *name) {
    double size = NUM2DBL(value);
    if (!(isfinite(size) && size > 0.0)) {
        rb_raise(rb_eArgError, "%s must be a positive, finite size, got %" PRIsVALUE, name, value);
    }
    return size;
}

/* TileSweep.new(grid, tile_width, tile_height) — a sweep over a SolidGrid's
 * cells at that tile size, which keeps the grid alive. TypeError for anything
 * but a grid; ArgumentError for a tile size that is not positive and finite. */
static VALUE tile_sweep_s_new(VALUE klass, VALUE grid, VALUE tile_width, VALUE tile_height) {
    rgame_solid_grid *cells = rgame_util_solid_grid(grid);
    double width = tile_size(tile_width, "tile_width");
    double height = tile_size(tile_height, "tile_height");

    tile_sweep_ref *ref;
    VALUE object = TypedData_Make_Struct(klass, tile_sweep_ref, &tile_sweep_data_type, ref);
    live_sweeps++;
    ref->grid = grid;
    ref->sweep = (rgame_tile_sweep){ .grid = cells, .tile_width = width, .tile_height = height };
    return object;
}

static VALUE tile_sweep_grid(VALUE self) { return unwrap(self)->grid; }
static VALUE tile_sweep_tile_width(VALUE self) { return DBL2NUM(unwrap(self)->sweep.tile_width); }
static VALUE tile_sweep_tile_height(VALUE self) { return DBL2NUM(unwrap(self)->sweep.tile_height); }

static void refuse_non_finite(double values[], int count) {
    for (int i = 0; i < count; i++) {
        if (!isfinite(values[i])) {
            rb_raise(rb_eFloatDomainError, "a box cannot be resolved at %f", values[i]);
        }
    }
}

/* A step with no movement returns the box where it is, whatever the numbers;
 * any other step through a non-finite number is a FloatDomainError. */
static VALUE resolve(VALUE self, VALUE x, VALUE y, VALUE w, VALUE h, VALUE delta,
                     double (*axis)(const rgame_tile_sweep *, double, double, double, double, double)) {
    double values[] = { NUM2DBL(x), NUM2DBL(y), NUM2DBL(w), NUM2DBL(h), NUM2DBL(delta) };
    if (values[4] != 0.0) {
        refuse_non_finite(values, 5);
    }
    return DBL2NUM(axis(&unwrap(self)->sweep, values[0], values[1], values[2], values[3], values[4]));
}

/* resolve_x(x, y, w, h, dx) — where the box's left edge lands moving dx,
 * snapped flush against a solid tile it would enter. Always a Float. */
static VALUE tile_sweep_resolve_x(VALUE self, VALUE x, VALUE y, VALUE w, VALUE h, VALUE dx) {
    return resolve(self, x, y, w, h, dx, rgame_tile_sweep_resolve_x);
}

/* resolve_y(x, y, w, h, dy) — the mirror of resolve_x. */
static VALUE tile_sweep_resolve_y(VALUE self, VALUE x, VALUE y, VALUE w, VALUE h, VALUE dy) {
    return resolve(self, x, y, w, h, dy, rgame_tile_sweep_resolve_y);
}

/* travel?(x, y, w, h, dx, dy) — whether the box travels (dx, dy) without any
 * resolve along the way falling short of where it was heading. Sound for a
 * walker stepping under a quarter tile at a time. FloatDomainError for a
 * non-finite number; ArgumentError for a travel too long to sweep. */
static VALUE tile_sweep_travel_p(VALUE self, VALUE x, VALUE y, VALUE w, VALUE h, VALUE dx, VALUE dy) {
    double values[] = { NUM2DBL(x), NUM2DBL(y), NUM2DBL(w), NUM2DBL(h), NUM2DBL(dx), NUM2DBL(dy) };
    refuse_non_finite(values, 6);

    rgame_tile_sweep *sweep = &unwrap(self)->sweep;
    double windows = rgame_tile_sweep_travel_windows(sweep, values[4], values[5]);
    if (windows > (double)INT32_MAX) {
        rb_raise(rb_eArgError, "a travel of (%f, %f) is too long to sweep", values[4], values[5]);
    }
    return rgame_tile_sweep_travel(sweep, values[0], values[1], values[2], values[3], values[4], values[5])
               ? Qtrue
               : Qfalse;
}

/* TileSweep.debug_live_sweeps — how many sweeps are allocated. Test-only, and
 * named so. */
static VALUE tile_sweep_s_debug_live_sweeps(VALUE klass) {
    (void)klass;
    return LONG2NUM(live_sweeps);
}

void rgame_init_tile_sweep(VALUE mUtil) {
    VALUE cTileSweep = rb_define_class_under(mUtil, "TileSweep", rb_cObject);

    rb_undef_alloc_func(cTileSweep);
    rb_define_singleton_method(cTileSweep, "new", tile_sweep_s_new, 3);
    rb_define_singleton_method(cTileSweep, "debug_live_sweeps", tile_sweep_s_debug_live_sweeps, 0);

    rb_define_method(cTileSweep, "grid", tile_sweep_grid, 0);
    rb_define_method(cTileSweep, "tile_width", tile_sweep_tile_width, 0);
    rb_define_method(cTileSweep, "tile_height", tile_sweep_tile_height, 0);
    rb_define_method(cTileSweep, "resolve_x", tile_sweep_resolve_x, 5);
    rb_define_method(cTileSweep, "resolve_y", tile_sweep_resolve_y, 5);
    rb_define_method(cTileSweep, "travel?", tile_sweep_travel_p, 6);
}
