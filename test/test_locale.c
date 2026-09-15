#include <check.h>
#include <string.h>

#include "app/locale.h"
#include "rgame/core.h"
#include "suites.h"

/* --- rgame_locale_append (pure) --- */

START_TEST(joins_language_and_country_with_a_hyphen) {
    char out[16];
    size_t length = rgame_locale_append(out, sizeof out, 0, "de", "AT");

    ck_assert_uint_eq(length, 5);
    ck_assert_str_eq(out, "de-AT");
}
END_TEST

START_TEST(writes_a_language_alone_when_there_is_no_country) {
    char out[16];
    size_t length = rgame_locale_append(out, sizeof out, 0, "en", NULL);
    length = rgame_locale_append(out, sizeof out, length, "fr", "");

    ck_assert_uint_eq(length, 5);
    ck_assert_str_eq(out, "en,fr");
}
END_TEST

START_TEST(separates_locales_with_a_comma_and_no_trailing_one) {
    char out[32];
    size_t length = rgame_locale_append(out, sizeof out, 0, "de", "AT");
    length = rgame_locale_append(out, sizeof out, length, "en", NULL);
    length = rgame_locale_append(out, sizeof out, length, "fr", "CA");

    ck_assert_uint_eq(length, 14);
    ck_assert_str_eq(out, "de-AT,en,fr-CA");
}
END_TEST

START_TEST(skips_a_locale_without_a_language) {
    char out[16];
    size_t length = rgame_locale_append(out, sizeof out, 0, "de", NULL);
    length = rgame_locale_append(out, sizeof out, length, NULL, "AT");
    length = rgame_locale_append(out, sizeof out, length, "", "US");

    ck_assert_uint_eq(length, 2);
    ck_assert_str_eq(out, "de");
}
END_TEST

START_TEST(truncates_to_the_capacity_and_still_reports_the_whole_length) {
    char out[3];
    size_t length = rgame_locale_append(out, sizeof out, 0, "de", "AT");

    ck_assert_uint_eq(length, 5);
    ck_assert_str_eq(out, "de");
}
END_TEST

START_TEST(fits_exactly_when_the_capacity_leaves_room_for_the_nul) {
    char out[6];
    size_t length = rgame_locale_append(out, sizeof out, 0, "de", "AT");

    ck_assert_uint_lt(length, sizeof out);
    ck_assert_str_eq(out, "de-AT");
}
END_TEST

START_TEST(keeps_counting_after_the_buffer_is_full) {
    char out[4];
    size_t length = rgame_locale_append(out, sizeof out, 0, "de", "AT");
    length = rgame_locale_append(out, sizeof out, length, "en", "GB");

    ck_assert_uint_eq(length, 11);
    ck_assert_str_eq(out, "de-");
}
END_TEST

START_TEST(writes_nothing_with_no_capacity) {
    size_t length = rgame_locale_append(NULL, 0, 0, "de", "AT");

    ck_assert_uint_eq(length, 5);
}
END_TEST

/* --- rgame_preferred_locales, over whatever this machine prefers --- */

START_TEST(preferred_locales_truncated_to_three_bytes_is_a_prefix_of_the_whole) {
    char whole[512];
    size_t needed = rgame_preferred_locales(whole, sizeof whole);
    ck_assert_uint_lt(needed, sizeof whole);

    char small[3];
    memset(small, 'x', sizeof small);
    size_t reported = rgame_preferred_locales(small, sizeof small);

    ck_assert_uint_eq(reported, needed);
    ck_assert_uint_eq(strlen(small), needed < 2 ? needed : 2);
    ck_assert_int_eq(strncmp(small, whole, strlen(small)), 0);
}
END_TEST

START_TEST(preferred_locales_with_no_capacity_reports_the_size_needed) {
    char whole[512];
    size_t needed = rgame_preferred_locales(whole, sizeof whole);

    ck_assert_uint_eq(rgame_preferred_locales(NULL, 0), needed);
}
END_TEST

Suite *locale_suite(void) {
    Suite *suite = suite_create("locale");

    TCase *append = tcase_create("append");
    tcase_add_test(append, joins_language_and_country_with_a_hyphen);
    tcase_add_test(append, writes_a_language_alone_when_there_is_no_country);
    tcase_add_test(append, separates_locales_with_a_comma_and_no_trailing_one);
    tcase_add_test(append, skips_a_locale_without_a_language);
    tcase_add_test(append, truncates_to_the_capacity_and_still_reports_the_whole_length);
    tcase_add_test(append, fits_exactly_when_the_capacity_leaves_room_for_the_nul);
    tcase_add_test(append, keeps_counting_after_the_buffer_is_full);
    tcase_add_test(append, writes_nothing_with_no_capacity);
    suite_add_tcase(suite, append);

    TCase *preferred = tcase_create("preferred");
    tcase_add_test(preferred, preferred_locales_truncated_to_three_bytes_is_a_prefix_of_the_whole);
    tcase_add_test(preferred, preferred_locales_with_no_capacity_reports_the_size_needed);
    suite_add_tcase(suite, preferred);

    return suite;
}
