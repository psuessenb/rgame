#ifndef CTEST_INTERNAL_H
#define CTEST_INTERNAL_H

/*
 * Implementation helpers shared between core.c and its tests (test/).
 * Not part of the public API in include/ctest/core.h — deliberately kept
 * out of there so the public header stays minimal for future Ruby binding.
 */

/* Advances angle_degrees by delta_degrees and wraps the result into [0, 360). */
double ctest_wrap_angle_degrees(double angle_degrees, double delta_degrees);

#endif /* CTEST_INTERNAL_H */
