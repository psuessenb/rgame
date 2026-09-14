/*
 * solid_grid.c — the solidity store of a tile grid. Pure; see solid_grid.h.
 */

#include "solid_grid.h"

#include <stdlib.h>

bool rgame_solid_grid_size_ok(int64_t width, int64_t height) {
    return width >= 0 && height >= 0 && (height == 0 || width <= INT32_MAX / height);
}

bool rgame_solid_grid_init(rgame_solid_grid *grid, int32_t width, int32_t height) {
    if (!rgame_solid_grid_size_ok(width, height)) {
        return false;
    }
    size_t count = (size_t)width * (size_t)height;
    uint8_t *cells = NULL;
    if (count > 0) {
        cells = calloc(count, 1);
        if (!cells) {
            return false;
        }
    }
    grid->width = width;
    grid->height = height;
    grid->cells = cells;
    grid->revision = 0;
    return true;
}

void rgame_solid_grid_free(rgame_solid_grid *grid) {
    free(grid->cells);
    grid->cells = NULL;
    grid->width = 0;
    grid->height = 0;
}

bool rgame_solid_grid_inside(const rgame_solid_grid *grid, int32_t col, int32_t row) {
    return col >= 0 && row >= 0 && col < grid->width && row < grid->height;
}

bool rgame_solid_grid_solid(const rgame_solid_grid *grid, int32_t col, int32_t row) {
    return rgame_solid_grid_inside(grid, col, row) && grid->cells[row * grid->width + col];
}

bool rgame_solid_grid_set(rgame_solid_grid *grid, int32_t col, int32_t row, bool solid) {
    if (!rgame_solid_grid_inside(grid, col, row)) {
        return false;
    }
    uint8_t *cell = &grid->cells[row * grid->width + col];
    uint8_t value = solid ? 1 : 0;
    if (*cell != value) {
        *cell = value;
        grid->revision++;
    }
    return true;
}
