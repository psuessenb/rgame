#ifndef RGAME_UTIL_EXT_H
#define RGAME_UTIL_EXT_H

#include <ruby.h>

/*
 * Each Ruby-visible class in this extension exposes one init function, and
 * util_ext.c calls them all. Adding a class means adding a file and one line
 * there — rather than editing an unrelated class's file, which is where
 * Init_util_ext used to live.
 */

void rgame_init_tensor(VALUE mUtil);
void rgame_init_color(VALUE mUtil);
void rgame_init_solid_grid(VALUE mUtil);
void rgame_init_route_search(VALUE mUtil);

/*
 * The two things a RouteSearch needs from the SolidGrid binding: the grid
 * behind a Ruby object (TypeError for anything else), and the one reading of a
 * cell coordinate both classes share — an Integer or a TypeError, and false
 * for an Integer too large to be inside any grid.
 */
#include <stdbool.h>
#include "solid_grid.h"

rgame_solid_grid *rgame_util_solid_grid(VALUE value);
bool rgame_util_cell_coordinate(VALUE value, int32_t *out);

#endif /* RGAME_UTIL_EXT_H */
