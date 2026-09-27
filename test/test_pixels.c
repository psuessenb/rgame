#include <check.h>

#include "graphics/pixels.h"
#include "suites.h"

/* --- scaling one byte by another --- */

START_TEST(every_scale_rounds_to_the_nearest_byte) {
    /* Exhaustive, because the shift trick in pixels.h is only obviously right
     * for the pairs someone thought to try. value * by / 255 never lands on a
     * half, so rounding to the nearest byte has one answer. */
    for (unsigned int value = 0; value < 256; value++) {
        for (unsigned int by = 0; by < 256; by++) {
            unsigned int nearest = ((2u * value * by) + 255u) / 510u;
            ck_assert_uint_eq(rgame_pixels_scale((unsigned char)value, (unsigned char)by),
                              nearest);
        }
    }
}
END_TEST

START_TEST(a_scale_by_255_changes_nothing) {
    for (unsigned int value = 0; value < 256; value++) {
        ck_assert_uint_eq(rgame_pixels_scale((unsigned char)value, 255), value);
    }
}
END_TEST

/* --- premultiplying a decoded image --- */

START_TEST(an_opaque_pixel_is_unchanged) {
    unsigned char rgba[4] = { 12, 34, 56, 255 };

    rgame_pixels_premultiply(rgba, 1);

    ck_assert_uint_eq(rgba[0], 12);
    ck_assert_uint_eq(rgba[1], 34);
    ck_assert_uint_eq(rgba[2], 56);
    ck_assert_uint_eq(rgba[3], 255);
}
END_TEST

START_TEST(a_fully_transparent_pixel_becomes_zero) {
    /* The black a PNG usually stores here would otherwise be averaged into
     * every filtered edge. White is the harder case: nothing zero to begin. */
    unsigned char rgba[4] = { 255, 255, 255, 0 };

    rgame_pixels_premultiply(rgba, 1);

    ck_assert_uint_eq(rgba[0], 0);
    ck_assert_uint_eq(rgba[1], 0);
    ck_assert_uint_eq(rgba[2], 0);
    ck_assert_uint_eq(rgba[3], 0);
}
END_TEST

START_TEST(a_half_transparent_pixel_halves_its_colour_rounded) {
    unsigned char rgba[4] = { 255, 100, 1, 128 };

    rgame_pixels_premultiply(rgba, 1);

    ck_assert_uint_eq(rgba[0], 128); /* 128.0 */
    ck_assert_uint_eq(rgba[1], 50);  /* 50.2 */
    ck_assert_uint_eq(rgba[2], 1);   /* 0.502 rounds up, where truncating gives 0 */
    ck_assert_uint_eq(rgba[3], 128);
}
END_TEST

START_TEST(only_the_pixels_counted_are_touched) {
    unsigned char rgba[8] = { 200, 200, 200, 0, 200, 200, 200, 0 };

    rgame_pixels_premultiply(rgba, 1);

    ck_assert_uint_eq(rgba[0], 0);
    ck_assert_uint_eq(rgba[4], 200);
}
END_TEST

START_TEST(an_empty_buffer_is_left_alone) {
    unsigned char rgba[4] = { 200, 200, 200, 0 };

    rgame_pixels_premultiply(rgba, 0);
    rgame_pixels_premultiply(NULL, 0);

    ck_assert_uint_eq(rgba[0], 200);
}
END_TEST

Suite *pixels_suite(void) {
    Suite *suite = suite_create("pixels");

    TCase *tc_scale = tcase_create("scale");
    tcase_add_test(tc_scale, every_scale_rounds_to_the_nearest_byte);
    tcase_add_test(tc_scale, a_scale_by_255_changes_nothing);
    suite_add_tcase(suite, tc_scale);

    TCase *tc_premultiply = tcase_create("premultiply");
    tcase_add_test(tc_premultiply, an_opaque_pixel_is_unchanged);
    tcase_add_test(tc_premultiply, a_fully_transparent_pixel_becomes_zero);
    tcase_add_test(tc_premultiply, a_half_transparent_pixel_halves_its_colour_rounded);
    tcase_add_test(tc_premultiply, only_the_pixels_counted_are_touched);
    tcase_add_test(tc_premultiply, an_empty_buffer_is_left_alone);
    suite_add_tcase(suite, tc_premultiply);

    return suite;
}
