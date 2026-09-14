#ifndef RGAME_SOLID_GRID_H
#define RGAME_SOLID_GRID_H

#include <stdbool.h>
#include <stdint.h>

/*
 * Which cells of a tile grid are solid — pure, no Ruby, no SDL, no GL.
 *
 * This is the one store of a tile world's solidity: the blockers that stop a
 * walker and the route search that plans one both read it, so a cell changed
 * here is changed for both at once and the two cannot disagree about a wall.
 *
 * `revision` is how a reader that keeps something derived from the cells (a
 * search's region labels) knows the cells have moved under it. It changes on
 * every write that changes a cell and on no other, so a derived value keyed to
 * it is rebuilt exactly when it has to be.
 *
 * Anything outside the grid is open, which is what a tile map answers past its
 * edges.
 */

typedef struct {
    int32_t width;
    int32_t height;
    uint8_t *cells;    /* width * height, row-major; 1 solid, 0 open */
    uint64_t revision; /* moves whenever a cell changes, and only then — and 64
                          bits, so it never wraps back onto a value a reader kept */
} rgame_solid_grid;

/* Whether a grid of this size can exist: neither side negative, and the cell
 * count within int32_t, so every in-bounds flat index fits the type the search
 * stores. Zero on either side is a valid, empty grid. */
bool rgame_solid_grid_size_ok(int64_t width, int64_t height);

/* Every cell open, revision 0. False — with nothing to free — for a size that is
 * not ok or when allocation fails. */
bool rgame_solid_grid_init(rgame_solid_grid *grid, int32_t width, int32_t height);
void rgame_solid_grid_free(rgame_solid_grid *grid);

bool rgame_solid_grid_inside(const rgame_solid_grid *grid, int32_t col, int32_t row);

/* False outside the grid. */
bool rgame_solid_grid_solid(const rgame_solid_grid *grid, int32_t col, int32_t row);

/* False, changing nothing, for a cell outside the grid. */
bool rgame_solid_grid_set(rgame_solid_grid *grid, int32_t col, int32_t row, bool solid);

#endif /* RGAME_SOLID_GRID_H */
