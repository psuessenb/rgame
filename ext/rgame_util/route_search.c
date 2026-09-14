/*
 * route_search.c — regions and A* over a solid grid. Pure; see route_search.h.
 *
 * Costs are doubles and are never contracted into fused multiply-adds: two
 * routes of equal cost are told apart by comparing sums, and a compiler that
 * fused one of them would pick a different, equally cheap route on one machine
 * than on another.
 */

#include "route_search.h"

#include <stdlib.h>
#include <string.h>

#ifdef __clang__
#pragma STDC FP_CONTRACT OFF
#endif

static const double DIAGONAL = 1.4142135623730951;
static const double DIAGONAL_EXTRA = 1.4142135623730951 - 1.0;

bool rgame_route_search_init(rgame_route_search *search, const rgame_solid_grid *grid) {
    memset(search, 0, sizeof(*search));
    search->grid = grid;
    search->cell_count = grid->width * grid->height;

    size_t count = search->cell_count > 0 ? (size_t)search->cell_count : 1;
    search->regions = malloc(count * sizeof(int32_t));
    search->flood = malloc(count * sizeof(int32_t));
    search->cost = malloc(count * sizeof(double));
    search->parent = malloc(count * sizeof(int32_t));
    search->seen = calloc(count, sizeof(uint32_t));
    search->closed = calloc(count, sizeof(uint32_t));
    search->route = malloc(count * sizeof(int32_t));

    if (!search->regions || !search->flood || !search->cost || !search->parent || !search->seen ||
        !search->closed || !search->route) {
        rgame_route_search_free(search);
        return false;
    }
    return true;
}

void rgame_route_search_free(rgame_route_search *search) {
    free(search->regions);
    free(search->flood);
    free(search->cost);
    free(search->parent);
    free(search->seen);
    free(search->closed);
    free(search->heap_cell);
    free(search->heap_total);
    free(search->heap_remaining);
    free(search->route);
    memset(search, 0, sizeof(*search));
}

int rgame_route_neighbours(const rgame_solid_grid *grid, int32_t index, int32_t cells[8],
                           double steps[8]) {
    int32_t width = grid->width;
    int32_t col = index % width;
    const uint8_t *solid = grid->cells;
    bool west = col > 0 && !solid[index - 1];
    bool east = col < width - 1 && !solid[index + 1];
    bool north = index >= width && !solid[index - width];
    bool south = index < grid->width * grid->height - width && !solid[index + width];

    int count = 0;
    if (west) { cells[count] = index - 1; steps[count++] = 1.0; }
    if (east) { cells[count] = index + 1; steps[count++] = 1.0; }
    if (north) { cells[count] = index - width; steps[count++] = 1.0; }
    if (south) { cells[count] = index + width; steps[count++] = 1.0; }
    if (north && west && !solid[index - width - 1]) { cells[count] = index - width - 1; steps[count++] = DIAGONAL; }
    if (north && east && !solid[index - width + 1]) { cells[count] = index - width + 1; steps[count++] = DIAGONAL; }
    if (south && west && !solid[index + width - 1]) { cells[count] = index + width - 1; steps[count++] = DIAGONAL; }
    if (south && east && !solid[index + width + 1]) { cells[count] = index + width + 1; steps[count++] = DIAGONAL; }
    return count;
}

/* --- regions --- */

static void claim(rgame_route_search *search, int32_t index, int32_t label, int32_t *top) {
    if (search->grid->cells[index] || search->regions[index] != -1) {
        return;
    }
    search->regions[index] = label;
    search->flood[(*top)++] = index;
}

static void label_regions(rgame_route_search *search) {
    const rgame_solid_grid *grid = search->grid;
    int32_t width = grid->width;
    int32_t count = search->cell_count;
    for (int32_t index = 0; index < count; index++) {
        search->regions[index] = -1;
    }

    int32_t label = 0;
    for (int32_t seed = 0; seed < count; seed++) {
        if (grid->cells[seed] || search->regions[seed] != -1) {
            continue;
        }
        int32_t top = 0;
        claim(search, seed, label, &top);
        while (top > 0) {
            int32_t index = search->flood[--top];
            int32_t col = index % width;
            if (col > 0) { claim(search, index - 1, label, &top); }
            if (col < width - 1) { claim(search, index + 1, label, &top); }
            if (index >= width) { claim(search, index - width, label, &top); }
            if (index < count - width) { claim(search, index + width, label, &top); }
        }
        label++;
    }

    search->labelled = true;
    search->labelled_at = grid->revision;
}

int32_t rgame_route_region(rgame_route_search *search, int32_t col, int32_t row) {
    if (!rgame_solid_grid_inside(search->grid, col, row)) {
        return -1;
    }
    if (!search->labelled || search->labelled_at != search->grid->revision) {
        label_regions(search);
    }
    return search->regions[row * search->grid->width + col];
}

/* --- the heap: parallel arrays, ordered by total then remaining --- */

static bool heap_reserve(rgame_route_search *search) {
    if (search->heap_size < search->heap_capacity) {
        return true;
    }
    size_t capacity = search->heap_capacity ? search->heap_capacity * 2 : 64;
    int32_t *cells = realloc(search->heap_cell, capacity * sizeof(int32_t));
    if (!cells) {
        return false;
    }
    search->heap_cell = cells;
    double *totals = realloc(search->heap_total, capacity * sizeof(double));
    if (!totals) {
        return false;
    }
    search->heap_total = totals;
    double *remainings = realloc(search->heap_remaining, capacity * sizeof(double));
    if (!remainings) {
        return false;
    }
    search->heap_remaining = remainings;
    search->heap_capacity = capacity;
    return true;
}

static bool push(rgame_route_search *search, int32_t index, double total, double remaining) {
    if (!heap_reserve(search)) {
        return false;
    }
    int32_t *cell = search->heap_cell;
    double *totals = search->heap_total;
    double *remainings = search->heap_remaining;
    size_t slot = search->heap_size++;
    while (slot > 0) {
        size_t up = (slot - 1) >> 1;
        if (totals[up] < total || (totals[up] == total && remainings[up] <= remaining)) {
            break;
        }
        cell[slot] = cell[up];
        totals[slot] = totals[up];
        remainings[slot] = remainings[up];
        slot = up;
    }
    cell[slot] = index;
    totals[slot] = total;
    remainings[slot] = remaining;
    return true;
}

static int32_t pop(rgame_route_search *search) {
    int32_t *cell = search->heap_cell;
    double *totals = search->heap_total;
    double *remainings = search->heap_remaining;
    int32_t top = cell[0];
    size_t size = --search->heap_size;
    if (size == 0) {
        return top;
    }

    int32_t index = cell[size];
    double total = totals[size];
    double remaining = remainings[size];
    size_t slot = 0;
    size_t child;
    while ((child = (slot << 1) + 1) < size) {
        size_t right = child + 1;
        if (right < size && (totals[right] < totals[child] ||
                             (totals[right] == totals[child] && remainings[right] < remainings[child]))) {
            child = right;
        }
        if (total < totals[child] || (total == totals[child] && remaining <= remainings[child])) {
            break;
        }
        cell[slot] = cell[child];
        totals[slot] = totals[child];
        remainings[slot] = remainings[child];
        slot = child;
    }
    cell[slot] = index;
    totals[slot] = total;
    remainings[slot] = remaining;
    return top;
}

/* --- A* --- */

static void next_generation(rgame_route_search *search) {
    if (++search->generation == 0) {
        size_t count = search->cell_count > 0 ? (size_t)search->cell_count : 1;
        memset(search->seen, 0, count * sizeof(uint32_t));
        memset(search->closed, 0, count * sizeof(uint32_t));
        search->generation = 1;
    }
}

static bool relax(rgame_route_search *search, int32_t from, int32_t to, double cost, int32_t goal_col,
                  int32_t goal_row) {
    uint32_t generation = search->generation;
    if (search->closed[to] == generation) {
        return true;
    }
    if (search->seen[to] == generation && search->cost[to] <= cost) {
        return true;
    }

    search->seen[to] = generation;
    search->cost[to] = cost;
    search->parent[to] = from;
    int32_t width = search->grid->width;
    int32_t dx = abs(to % width - goal_col);
    int32_t dy = abs(to / width - goal_row);
    double remaining = dx < dy ? (double)dy + DIAGONAL_EXTRA * dx : (double)dx + DIAGONAL_EXTRA * dy;
    return push(search, to, cost + remaining, remaining);
}

static rgame_route_result search_route(rgame_route_search *search, int32_t start, int32_t goal,
                                       int32_t goal_col, int32_t goal_row) {
    next_generation(search);
    search->heap_size = 0;
    if (!relax(search, -1, start, 0.0, goal_col, goal_row)) {
        return RGAME_ROUTE_NO_MEMORY;
    }

    int32_t cells[8];
    double steps[8];
    while (search->heap_size > 0) {
        int32_t index = pop(search);
        if (search->closed[index] == search->generation) {
            continue;
        }
        if (index == goal) {
            return RGAME_ROUTE_FOUND;
        }

        search->closed[index] = search->generation;
        int count = rgame_route_neighbours(search->grid, index, cells, steps);
        double cost = search->cost[index];
        for (int i = 0; i < count; i++) {
            if (!relax(search, index, cells[i], cost + steps[i], goal_col, goal_row)) {
                return RGAME_ROUTE_NO_MEMORY;
            }
        }
    }
    /* Unreachable once regions agree the two ends are joined. */
    return RGAME_ROUTE_NONE;
}

static void collect_route(rgame_route_search *search, int32_t goal) {
    int32_t length = 0;
    for (int32_t index = goal; index != -1; index = search->parent[index]) {
        length++;
    }
    int32_t slot = length;
    for (int32_t index = goal; index != -1; index = search->parent[index]) {
        search->route[--slot] = index;
    }
    search->route_length = length;
}

rgame_route_result rgame_route_find(rgame_route_search *search, int32_t from_col, int32_t from_row,
                                    int32_t to_col, int32_t to_row) {
    search->route_length = 0;
    int32_t from_region = rgame_route_region(search, from_col, from_row);
    if (from_region == -1 || from_region != rgame_route_region(search, to_col, to_row)) {
        return RGAME_ROUTE_NONE;
    }

    int32_t width = search->grid->width;
    int32_t goal = to_row * width + to_col;
    rgame_route_result result = search_route(search, from_row * width + from_col, goal, to_col, to_row);
    if (result == RGAME_ROUTE_FOUND) {
        collect_route(search, goal);
    }
    return result;
}
