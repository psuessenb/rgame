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

#endif /* RGAME_UTIL_EXT_H */
