#ifndef RGAME_ROUTE_SEARCH_H
#define RGAME_ROUTE_SEARCH_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "solid_grid.h"

/*
 * Connected regions and A* routes over a solid grid — pure, no Ruby, no SDL.
 *
 * A search reads its grid and never writes it. Everything it keeps between
 * queries lives in the search, so any number of searches may read one grid —
 * which is what lets many walkers plan over the one store a tile world's
 * blockers also read.
 *
 * The grid is 8-connected with octile costs (1 straight, sqrt 2 diagonal), and a
 * diagonal step is allowed only when both orthogonal cells beside it are open,
 * so a route never cuts the corner of a solid cell. That rule is
 * rgame_route_neighbours, and every search over the grid goes through it.
 *
 * Regions are labelled by an orthogonal flood fill the first time one is asked
 * for, and again whenever the grid's revision has moved since — so an
 * unreachable goal, the answer A* is slowest to give, is a lookup, and it stays
 * right when the grid changes.
 *
 * A search allocates its per-cell buffers once, at init, and marks which
 * entries are current with a generation stamp, so a query costs nothing
 * proportional to the grid. The heap grows to the largest query seen and never
 * shrinks: a repeated query allocates nothing.
 */

typedef enum {
    RGAME_ROUTE_FOUND,
    RGAME_ROUTE_NONE,     /* an end is solid, outside, or in another region */
    RGAME_ROUTE_NO_MEMORY /* the heap could not grow; the search is still usable */
} rgame_route_result;

typedef struct {
    const rgame_solid_grid *grid;
    int32_t cell_count;

    int32_t *regions; /* per cell; -1 solid */
    int32_t *flood;   /* the flood fill's stack */
    bool labelled;
    uint64_t labelled_at; /* the grid revision the labels describe */

    double *cost;
    int32_t *parent;
    uint32_t *seen;
    uint32_t *closed;
    uint32_t generation; /* stamps; wrapping clears them */

    int32_t *heap_cell;
    double *heap_total;
    double *heap_remaining;
    size_t heap_size;
    size_t heap_capacity; /* grows, never shrinks */

    int32_t *route; /* flat indices, start first, after RGAME_ROUTE_FOUND */
    int32_t route_length;
} rgame_route_search;

/* The grid must outlive the search. False, with nothing to free, when
 * allocation fails. */
bool rgame_route_search_init(rgame_route_search *search, const rgame_solid_grid *grid);
void rgame_route_search_free(rgame_route_search *search);

/* The cells one step from `index` may reach, in the order a search relaxes them
 * (west, east, north, south, then the four diagonals), each with its step cost.
 * Returns how many were written, at most 8. */
int rgame_route_neighbours(const rgame_solid_grid *grid, int32_t index, int32_t cells[8],
                           double steps[8]);

/* The region label of a cell — two walkable cells share one exactly when a
 * route joins them — or -1 for a solid cell or one outside the grid. */
int32_t rgame_route_region(rgame_route_search *search, int32_t col, int32_t row);

/* The cheapest route from start to goal, both included, into search->route.
 * Ties between equally cheap routes go to the entry with the smaller remaining
 * estimate, so the same query always returns the same route. */
rgame_route_result rgame_route_find(rgame_route_search *search, int32_t from_col, int32_t from_row,
                                    int32_t to_col, int32_t to_row);

#endif /* RGAME_ROUTE_SEARCH_H */
