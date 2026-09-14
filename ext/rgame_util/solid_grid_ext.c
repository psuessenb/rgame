/*
 * solid_grid_ext.c — the Ruby binding for RGame::Util::SolidGrid.
 *
 * The store lives in solid_grid.{c,h}, which includes no ruby.h and is covered
 * directly by the Check suite. This file is argument checking and wrapping.
 *
 * A grid's size is fixed at construction and there is no allocator to reach it
 * any other way: a RouteSearch keeps a pointer into the grid it was built over,
 * sized to its cells, so a grid that could be re-initialized or copied into a
 * different size would leave that search indexing past the end.
 */

#include "util_ext.h"

#include "solid_grid.h"

static long live_grids = 0;

static void solid_grid_free(void *ptr) {
    rgame_solid_grid_free(ptr);
    xfree(ptr);
    live_grids--;
}

static size_t solid_grid_memsize(const void *ptr) {
    const rgame_solid_grid *grid = ptr;
    return sizeof(*grid) + (size_t)grid->width * (size_t)grid->height;
}

static const rb_data_type_t solid_grid_data_type = {
    .wrap_struct_name = "rgame_solid_grid",
    .function = {
        .dmark = NULL, /* no Ruby objects inside */
        .dfree = solid_grid_free,
        .dsize = solid_grid_memsize,
    },
    .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

rgame_solid_grid *rgame_util_solid_grid(VALUE value) {
    return rb_check_typeddata(value, &solid_grid_data_type);
}

/*
 * A cell coordinate: an Integer, or a TypeError. An Integer too large for the
 * grid's index type is not an error but a cell outside the grid, answered like
 * any other — which is why a Bignum is checked for before converting, where
 * NUM2INT would raise RangeError instead.
 */
bool rgame_util_cell_coordinate(VALUE value, int32_t *out) {
    if (FIXNUM_P(value)) {
        long long number = NUM2LL(value);
        if (number < INT32_MIN || number > INT32_MAX) {
            return false;
        }
        *out = (int32_t)number;
        return true;
    }
    if (RB_TYPE_P(value, T_BIGNUM)) {
        return false;
    }
    rb_raise(rb_eTypeError, "a cell coordinate must be an Integer, got %" PRIsVALUE,
             rb_obj_class(value));
}

static int64_t dimension(VALUE value, const char *name) {
    if (RB_TYPE_P(value, T_BIGNUM)) {
        rb_raise(rb_eArgError, "%s is too large for a grid", name);
    }
    if (!FIXNUM_P(value)) {
        rb_raise(rb_eTypeError, "%s must be an Integer, got %" PRIsVALUE, name, rb_obj_class(value));
    }
    return NUM2LL(value);
}

/* SolidGrid.new(width, height) — every cell open.
 *
 * Refuses a negative size, and one whose cell count passes 2**31 - 1, with
 * ArgumentError. A zero size is an empty grid with no inside. */
static VALUE solid_grid_s_new(VALUE klass, VALUE width_value, VALUE height_value) {
    int64_t width = dimension(width_value, "width");
    int64_t height = dimension(height_value, "height");
    if (width < 0 || height < 0) {
        rb_raise(rb_eArgError, "a grid cannot be %lldx%lld", (long long)width, (long long)height);
    }
    if (!rgame_solid_grid_size_ok(width, height)) {
        rb_raise(rb_eArgError, "a %lldx%lld grid has more cells than it can index", (long long)width,
                 (long long)height);
    }

    rgame_solid_grid *grid;
    VALUE object = TypedData_Make_Struct(klass, rgame_solid_grid, &solid_grid_data_type, grid);
    live_grids++;
    if (!rgame_solid_grid_init(grid, (int32_t)width, (int32_t)height)) {
        rb_memerror();
    }
    return object;
}

static VALUE solid_grid_width(VALUE self) { return INT2NUM(rgame_util_solid_grid(self)->width); }
static VALUE solid_grid_height(VALUE self) { return INT2NUM(rgame_util_solid_grid(self)->height); }

/* A count of the changes made to the grid: it moves whenever a cell changes and
 * only then, so something derived from the cells can tell whether it is stale. */
static VALUE solid_grid_revision(VALUE self) {
    return ULL2NUM(rgame_util_solid_grid(self)->revision);
}

/* solid?(col, row) — false outside the grid. */
static VALUE solid_grid_solid_p(VALUE self, VALUE col_value, VALUE row_value) {
    int32_t col = 0;
    int32_t row = 0;
    bool col_fits = rgame_util_cell_coordinate(col_value, &col);
    bool row_fits = rgame_util_cell_coordinate(row_value, &row);
    return col_fits && row_fits && rgame_solid_grid_solid(rgame_util_solid_grid(self), col, row)
               ? Qtrue
               : Qfalse;
}

/* set_solid(col, row, solid) — raises IndexError for a cell outside the grid,
 * since a write that silently went nowhere is a wall that is not there. */
static VALUE solid_grid_set_solid(VALUE self, VALUE col_value, VALUE row_value, VALUE solid) {
    int32_t col = 0;
    int32_t row = 0;
    bool col_fits = rgame_util_cell_coordinate(col_value, &col);
    bool row_fits = rgame_util_cell_coordinate(row_value, &row);
    rgame_solid_grid *grid = rgame_util_solid_grid(self);
    if (!col_fits || !row_fits || !rgame_solid_grid_set(grid, col, row, RTEST(solid))) {
        rb_raise(rb_eIndexError, "cell (%" PRIsVALUE ", %" PRIsVALUE ") is outside a %dx%d grid",
                 col_value, row_value, grid->width, grid->height);
    }
    return solid;
}

static VALUE solid_grid_inspect(VALUE self) {
    rgame_solid_grid *grid = rgame_util_solid_grid(self);
    return rb_sprintf("#<%" PRIsVALUE " %dx%d revision=%llu>", rb_obj_class(self), grid->width,
                      grid->height, (unsigned long long)grid->revision);
}

/* SolidGrid.debug_live_grids — how many grids are holding cells. Test-only, and
 * named so: it is what lets a spec see a grid's cells freed with it. */
static VALUE solid_grid_s_debug_live_grids(VALUE klass) {
    (void)klass;
    return LONG2NUM(live_grids);
}

void rgame_init_solid_grid(VALUE mUtil) {
    VALUE cSolidGrid = rb_define_class_under(mUtil, "SolidGrid", rb_cObject);

    rb_undef_alloc_func(cSolidGrid);
    rb_define_singleton_method(cSolidGrid, "new", solid_grid_s_new, 2);
    rb_define_singleton_method(cSolidGrid, "debug_live_grids", solid_grid_s_debug_live_grids, 0);

    rb_define_method(cSolidGrid, "width", solid_grid_width, 0);
    rb_define_method(cSolidGrid, "height", solid_grid_height, 0);
    rb_define_method(cSolidGrid, "revision", solid_grid_revision, 0);
    rb_define_method(cSolidGrid, "solid?", solid_grid_solid_p, 2);
    rb_define_method(cSolidGrid, "set_solid", solid_grid_set_solid, 3);
    rb_define_method(cSolidGrid, "inspect", solid_grid_inspect, 0);
}
