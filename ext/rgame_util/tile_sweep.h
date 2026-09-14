#ifndef RGAME_TILE_SWEEP_H
#define RGAME_TILE_SWEEP_H

#include <stdbool.h>
#include <stdint.h>

#include "solid_grid.h"

/*
 * An axis-aligned box against the solid tiles of a grid — pure, no Ruby, no
 * SDL, no GL.
 *
 * Two questions, answered by one piece of arithmetic so they cannot disagree:
 *
 * - **Resolve**: where does the box's left (top) edge land moving dx (dy)? A
 *   step that would enter a solid tile snaps the box flush against that tile's
 *   edge. Each axis is resolved on its own; feeding one axis the other's result
 *   (and so sliding along walls) is the caller's order to choose.
 * - **Travel**: can the box move by (dx, dy) without any resolve along the way
 *   falling short of where it was heading? This is how a route is checked
 *   against the same resolver that will stop the walker on it.
 *
 * Resolving assumes a step smaller than a tile: a longer one can pass through a
 * tile without seeing it. Travel is built for exactly that limit. It sweeps the
 * box in overlapping windows half a tile long at a quarter-tile stride, and
 * resolves each window X-then-Y and Y-then-X. Both orders together cover every
 * position between a window's ends, and the overlap covers a walker's own
 * X-then-Y step straddling two windows — so travel is sound for a walker whose
 * step is under a quarter tile.
 *
 * Anything outside the grid is open. Tile ranges are clamped to the grid before
 * any conversion to an integer, so no coordinate, however large, is undefined
 * behaviour or a long loop. A NaN coordinate reads as open ground; callers that
 * need to refuse one (the Ruby binding does) check before calling.
 */

typedef struct {
    const rgame_solid_grid *grid; /* must outlive the sweep */
    double tile_width;            /* > 0 */
    double tile_height;           /* > 0 */
} rgame_tile_sweep;

/* Where the box's left edge lands moving dx. dx of zero returns x unchanged. */
double rgame_tile_sweep_resolve_x(const rgame_tile_sweep *sweep, double x, double y, double w, double h,
                                  double dx);

/* Where the box's top edge lands moving dy. dy of zero returns y unchanged. */
double rgame_tile_sweep_resolve_y(const rgame_tile_sweep *sweep, double x, double y, double w, double h,
                                  double dy);

/* How many windows a travel of (dx, dy) sweeps — at least 1, or NaN for a NaN
 * delta. Exposed so a caller can refuse a travel too long to sweep before
 * starting it. */
double rgame_tile_sweep_travel_windows(const rgame_tile_sweep *sweep, double dx, double dy);

/* Whether the box at (x, y, w, h) travels (dx, dy) with no resolve along the
 * way falling short of the landing it was heading for. A NaN delta, or a travel
 * of more than INT32_MAX windows, is answered false without sweeping. */
bool rgame_tile_sweep_travel(const rgame_tile_sweep *sweep, double x, double y, double w, double h, double dx,
                             double dy);

#endif /* RGAME_TILE_SWEEP_H */
