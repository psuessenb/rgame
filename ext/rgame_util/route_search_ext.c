/*
 * route_search_ext.c — the Ruby binding for RGame::Util::RouteSearch.
 *
 * The search lives in route_search.{c,h}, pure and covered by the Check suite.
 * What this file adds is lifetime: the C search holds a pointer into the
 * SolidGrid it reads, so the Ruby object holds the grid too and marks it, and
 * the grid cannot be collected while a search over it is alive.
 */

#include "util_ext.h"

#include "route_search.h"

typedef struct {
    VALUE grid;
    rgame_route_search search;
    bool ready;
} route_search_ref;

static long live_searches = 0;

static void route_search_mark(void *ptr) {
    route_search_ref *ref = ptr;
    rb_gc_mark(ref->grid);
}

static void route_search_free(void *ptr) {
    route_search_ref *ref = ptr;
    if (ref->ready) {
        rgame_route_search_free(&ref->search);
    }
    xfree(ref);
    live_searches--;
}

static size_t route_search_memsize(const void *ptr) {
    const route_search_ref *ref = ptr;
    size_t cells = ref->ready ? (size_t)ref->search.cell_count : 0;
    size_t per_cell = 4 * sizeof(int32_t) + sizeof(double) + 2 * sizeof(uint32_t);
    size_t per_entry = sizeof(int32_t) + 2 * sizeof(double);
    return sizeof(*ref) + cells * per_cell + ref->search.heap_capacity * per_entry;
}

static const rb_data_type_t route_search_data_type = {
    .wrap_struct_name = "rgame_route_search",
    .function = {
        .dmark = route_search_mark,
        .dfree = route_search_free,
        .dsize = route_search_memsize,
    },
    .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

static rgame_route_search *unwrap(VALUE self) {
    route_search_ref *ref;
    TypedData_Get_Struct(self, route_search_ref, &route_search_data_type, ref);
    return &ref->search;
}

/* RouteSearch.new(grid) — a search over a SolidGrid, which it keeps alive. */
static VALUE route_search_s_new(VALUE klass, VALUE grid) {
    rgame_solid_grid *cells = rgame_util_solid_grid(grid);

    route_search_ref *ref;
    VALUE object = TypedData_Make_Struct(klass, route_search_ref, &route_search_data_type, ref);
    live_searches++;
    ref->grid = grid;
    if (!rgame_route_search_init(&ref->search, cells)) {
        rb_memerror();
    }
    ref->ready = true;
    return object;
}

static VALUE route_search_grid(VALUE self) {
    route_search_ref *ref;
    TypedData_Get_Struct(self, route_search_ref, &route_search_data_type, ref);
    return ref->grid;
}

/* region(col, row) — an Integer label two walkable cells share exactly when a
 * route joins them, or nil for a solid cell or one outside the grid. Labels are
 * recomputed on the first ask after the grid changes. */
static VALUE route_search_region(VALUE self, VALUE col_value, VALUE row_value) {
    int32_t col = 0;
    int32_t row = 0;
    bool col_fits = rgame_util_cell_coordinate(col_value, &col);
    bool row_fits = rgame_util_cell_coordinate(row_value, &row);
    if (!col_fits || !row_fits) {
        return Qnil;
    }
    int32_t region = rgame_route_region(unwrap(self), col, row);
    return region == -1 ? Qnil : INT2NUM(region);
}

/* find(from_col, from_row, to_col, to_row) — the cheapest route, both ends
 * included, as [[col, row], ...]; nil when either end is solid, outside the
 * grid, or in another region. Equally cheap routes are told apart the same way
 * every time. */
static VALUE route_search_find(VALUE self, VALUE from_col_value, VALUE from_row_value,
                               VALUE to_col_value, VALUE to_row_value) {
    int32_t from_col = 0;
    int32_t from_row = 0;
    int32_t to_col = 0;
    int32_t to_row = 0;
    bool fits = rgame_util_cell_coordinate(from_col_value, &from_col);
    fits = rgame_util_cell_coordinate(from_row_value, &from_row) && fits;
    fits = rgame_util_cell_coordinate(to_col_value, &to_col) && fits;
    fits = rgame_util_cell_coordinate(to_row_value, &to_row) && fits;
    if (!fits) {
        return Qnil;
    }

    rgame_route_search *search = unwrap(self);
    switch (rgame_route_find(search, from_col, from_row, to_col, to_row)) {
    case RGAME_ROUTE_NONE:
        return Qnil;
    case RGAME_ROUTE_NO_MEMORY:
        rb_memerror();
    case RGAME_ROUTE_FOUND:
        break;
    }

    int32_t width = search->grid->width;
    VALUE route = rb_ary_new_capa(search->route_length);
    for (int32_t i = 0; i < search->route_length; i++) {
        int32_t index = search->route[i];
        rb_ary_push(route, rb_assoc_new(INT2FIX(index % width), INT2FIX(index / width)));
    }
    return route;
}

/* RouteSearch.debug_live_searches — how many searches are holding buffers.
 * Test-only, and named so. */
static VALUE route_search_s_debug_live_searches(VALUE klass) {
    (void)klass;
    return LONG2NUM(live_searches);
}

void rgame_init_route_search(VALUE mUtil) {
    VALUE cRouteSearch = rb_define_class_under(mUtil, "RouteSearch", rb_cObject);

    rb_undef_alloc_func(cRouteSearch);
    rb_define_singleton_method(cRouteSearch, "new", route_search_s_new, 1);
    rb_define_singleton_method(cRouteSearch, "debug_live_searches", route_search_s_debug_live_searches, 0);

    rb_define_method(cRouteSearch, "grid", route_search_grid, 0);
    rb_define_method(cRouteSearch, "region", route_search_region, 2);
    rb_define_method(cRouteSearch, "find", route_search_find, 4);
}
