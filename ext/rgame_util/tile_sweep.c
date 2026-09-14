/*
 * tile_sweep.c — a box against a solid grid's tiles. Pure; see tile_sweep.h.
 */

#include "tile_sweep.h"

#include <math.h>

#ifdef __clang__
#pragma STDC FP_CONTRACT OFF
#endif

/* How far inside an edge a box's far side is measured, so a box resting flush
 * against a tile does not count as overlapping it. */
static const double EDGE_EPS = 1e-9;

/* A travel window's stride, as a fraction of a tile. A window spans two strides. */
static const double STRIDE = 0.25;

static bool tile_index(double edge, double tile_size, int32_t count, int32_t *out) {
    double index = floor(edge / tile_size);
    if (!(index >= 0.0 && index < (double)count)) {
        return false;
    }
    *out = (int32_t)index;
    return true;
}

static bool tile_span(double near_edge, double far_edge, double tile_size, int32_t count, int32_t *first,
                      int32_t *last) {
    double low = floor(near_edge / tile_size);
    double high = floor(far_edge / tile_size);
    if (isnan(low) || isnan(high)) {
        return false;
    }
    if (low < 0.0) {
        low = 0.0;
    }
    if (high > (double)count - 1.0) {
        high = (double)count - 1.0;
    }
    if (low > high) {
        return false;
    }
    *first = (int32_t)low;
    *last = (int32_t)high;
    return true;
}

static bool solid_in_column(const rgame_solid_grid *grid, int32_t col, int32_t first_row, int32_t last_row) {
    for (int32_t row = first_row; row <= last_row; row++) {
        if (grid->cells[row * grid->width + col]) {
            return true;
        }
    }
    return false;
}

static bool solid_in_row(const rgame_solid_grid *grid, int32_t row, int32_t first_col, int32_t last_col) {
    for (int32_t col = first_col; col <= last_col; col++) {
        if (grid->cells[row * grid->width + col]) {
            return true;
        }
    }
    return false;
}

double rgame_tile_sweep_resolve_x(const rgame_tile_sweep *sweep, double x, double y, double w, double h,
                                  double dx) {
    double landed = x + dx;
    if (dx == 0.0) {
        return landed;
    }

    const rgame_solid_grid *grid = sweep->grid;
    int32_t first_row = 0;
    int32_t last_row = 0;
    if (!tile_span(y, y + h - EDGE_EPS, sweep->tile_height, grid->height, &first_row, &last_row)) {
        return landed;
    }

    int32_t col = 0;
    if (dx > 0.0) {
        if (tile_index(landed + w - EDGE_EPS, sweep->tile_width, grid->width, &col) &&
            solid_in_column(grid, col, first_row, last_row)) {
            return col * sweep->tile_width - w;
        }
    } else if (tile_index(landed, sweep->tile_width, grid->width, &col) &&
               solid_in_column(grid, col, first_row, last_row)) {
        return (col + 1) * sweep->tile_width;
    }
    return landed;
}

double rgame_tile_sweep_resolve_y(const rgame_tile_sweep *sweep, double x, double y, double w, double h,
                                  double dy) {
    double landed = y + dy;
    if (dy == 0.0) {
        return landed;
    }

    const rgame_solid_grid *grid = sweep->grid;
    int32_t first_col = 0;
    int32_t last_col = 0;
    if (!tile_span(x, x + w - EDGE_EPS, sweep->tile_width, grid->width, &first_col, &last_col)) {
        return landed;
    }

    int32_t row = 0;
    if (dy > 0.0) {
        if (tile_index(landed + h - EDGE_EPS, sweep->tile_height, grid->height, &row) &&
            solid_in_row(grid, row, first_col, last_col)) {
            return row * sweep->tile_height - h;
        }
    } else if (tile_index(landed, sweep->tile_height, grid->height, &row) &&
               solid_in_row(grid, row, first_col, last_col)) {
        return (row + 1) * sweep->tile_height;
    }
    return landed;
}

/* Short of the intended landing: behind it, in the direction of travel. A
 * landing past it is not short, which is how CollisionSystem reads a source. */
static bool short_of(double landed, double intended, double delta) {
    return delta > 0.0 ? landed < intended : delta < 0.0 && landed > intended;
}

static bool window_clear(const rgame_tile_sweep *sweep, double x, double y, double w, double h, double dx,
                         double dy) {
    return !short_of(rgame_tile_sweep_resolve_x(sweep, x, y, w, h, dx), x + dx, dx) &&
           !short_of(rgame_tile_sweep_resolve_y(sweep, x + dx, y, w, h, dy), y + dy, dy) &&
           !short_of(rgame_tile_sweep_resolve_y(sweep, x, y, w, h, dy), y + dy, dy) &&
           !short_of(rgame_tile_sweep_resolve_x(sweep, x, y + dy, w, h, dx), x + dx, dx);
}

double rgame_tile_sweep_travel_windows(const rgame_tile_sweep *sweep, double dx, double dy) {
    double across = ceil(fabs(dx) / (sweep->tile_width * STRIDE));
    double down = ceil(fabs(dy) / (sweep->tile_height * STRIDE));
    if (isnan(across) || isnan(down)) {
        return NAN;
    }
    double steps = across > down ? across : down;
    return steps > 1.0 ? steps : 1.0;
}

bool rgame_tile_sweep_travel(const rgame_tile_sweep *sweep, double x, double y, double w, double h, double dx,
                             double dy) {
    double steps = rgame_tile_sweep_travel_windows(sweep, dx, dy);
    if (!(steps <= (double)INT32_MAX)) {
        return false;
    }
    int32_t count = (int32_t)steps;
    double step_x = dx / count;
    double step_y = dy / count;
    int32_t span = count < 2 ? count : 2;

    for (int32_t sample = 0; sample <= count - span; sample++) {
        if (!window_clear(sweep, x + step_x * sample, y + step_y * sample, w, h, step_x * span,
                          step_y * span)) {
            return false;
        }
    }
    return true;
}
