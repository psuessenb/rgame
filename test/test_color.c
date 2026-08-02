#include <check.h>

#include "color.h"
#include "suites.h"

/* --- packing --- */

START_TEST(components_round_trip_through_the_packed_form) {
    rgame_color c = rgame_color_rgba(1, 2, 3, 4);

    ck_assert_int_eq(rgame_color_r(c), 1);
    ck_assert_int_eq(rgame_color_g(c), 2);
    ck_assert_int_eq(rgame_color_b(c), 3);
    ck_assert_int_eq(rgame_color_a(c), 4);
}

END_TEST

START_TEST(the_packed_layout_is_rrggbbaa) {
    /* Pinned as a literal, not derived: the whole point of a documented packed
     * form is that a human can read #RRGGBBAA and get what they expect. */
    ck_assert_uint_eq(rgame_color_rgba(0xAA, 0xBB, 0xCC, 0xDD), 0xAABBCCDDu);
    ck_assert_uint_eq(rgame_color_rgba(255, 0, 0, 255), 0xFF0000FFu);
    ck_assert_uint_eq(rgame_color_rgba(0, 0, 255, 255), 0x0000FFFFu);
}

END_TEST

START_TEST(the_named_colours_are_what_they_claim) {
    ck_assert_int_eq(rgame_color_r(RGAME_COLOR_WHITE), 255);
    ck_assert_int_eq(rgame_color_a(RGAME_COLOR_WHITE), 255);

    ck_assert_int_eq(rgame_color_r(RGAME_COLOR_BLACK), 0);
    ck_assert_int_eq(rgame_color_a(RGAME_COLOR_BLACK), 255);

    ck_assert_int_eq(rgame_color_a(RGAME_COLOR_TRANSPARENT), 0);
}

END_TEST

START_TEST(components_are_clamped_rather_than_wrapping) {
    /* The C layer is total: out-of-range clamps. Wrapping would turn 256 into
     * 0, i.e. full brightness into none, which is the worst possible failure.
     * (The Ruby wrapper is stricter and raises instead — a Ruby caller passing
     * 300 has a bug worth hearing about.) */
    ck_assert_int_eq(rgame_color_r(rgame_color_rgba(300, 0, 0, 0)), 255);
    ck_assert_int_eq(rgame_color_r(rgame_color_rgba(-5, 0, 0, 0)), 0);
    ck_assert_int_eq(rgame_color_a(rgame_color_rgba(0, 0, 0, 999)), 255);
}

END_TEST

START_TEST(a_component_never_bleeds_into_its_neighbours) {
    /* An off-by-one shift would show up as green leaking into red. */
    ck_assert_uint_eq(rgame_color_rgba(255, 0, 0, 0), 0xFF000000u);
    ck_assert_uint_eq(rgame_color_rgba(0, 255, 0, 0), 0x00FF0000u);
    ck_assert_uint_eq(rgame_color_rgba(0, 0, 255, 0), 0x0000FF00u);
    ck_assert_uint_eq(rgame_color_rgba(0, 0, 0, 255), 0x000000FFu);
}

END_TEST

/* --- the byte order the vertex format depends on --- */

START_TEST(bytes_come_out_in_gl_order_red_first) {
    /* glColorPointer(4, GL_UNSIGNED_BYTE, ...) reads R, G, B, A in memory
     * order. This is the contract the draw queue's vertex format is built on;
     * getting it wrong tints everything and looks like a shader bug. */
    unsigned char out[4] = { 0 };
    rgame_color_bytes(rgame_color_rgba(0x11, 0x22, 0x33, 0x44), out);

    ck_assert_uint_eq(out[0], 0x11);
    ck_assert_uint_eq(out[1], 0x22);
    ck_assert_uint_eq(out[2], 0x33);
    ck_assert_uint_eq(out[3], 0x44);
}

END_TEST

START_TEST(bytes_are_not_the_packed_word_reinterpreted) {
    /*
     * The trap color.h warns about, pinned so nobody "optimises" the byte
     * writer into a memcpy of the packed uint32. On a little-endian machine
     * those bytes come out A, B, G, R — GL would read alpha as red.
     *
     * The assertion is written to hold on either endianness: it only claims
     * that *if* the reinterpretation differs from the correct order, the
     * correct order is still what rgame_color_bytes produced.
     */
    rgame_color c = rgame_color_rgba(0x11, 0x22, 0x33, 0x44);
    unsigned char correct[4];
    rgame_color_bytes(c, correct);

    unsigned char reinterpreted[4];
    for (int i = 0; i < 4; i++) {
        reinterpreted[i] = ((const unsigned char *)&c)[i];
    }

    ck_assert_uint_eq(correct[0], 0x11);
    /* Little-endian: reinterpreting really would be wrong. Big-endian: the two
     * agree, and there is nothing to warn about. Either way `correct` is right. */
    if (reinterpreted[0] != correct[0]) {
        ck_assert_uint_eq(reinterpreted[0], 0x44);
    }
}

END_TEST

Suite *color_suite(void) {
    Suite *suite = suite_create("color");

    TCase *tc_pack = tcase_create("packing");
    tcase_add_test(tc_pack, components_round_trip_through_the_packed_form);
    tcase_add_test(tc_pack, the_packed_layout_is_rrggbbaa);
    tcase_add_test(tc_pack, the_named_colours_are_what_they_claim);
    tcase_add_test(tc_pack, components_are_clamped_rather_than_wrapping);
    tcase_add_test(tc_pack, a_component_never_bleeds_into_its_neighbours);
    suite_add_tcase(suite, tc_pack);

    TCase *tc_bytes = tcase_create("gl_byte_order");
    tcase_add_test(tc_bytes, bytes_come_out_in_gl_order_red_first);
    tcase_add_test(tc_bytes, bytes_are_not_the_packed_word_reinterpreted);
    suite_add_tcase(suite, tc_bytes);

    return suite;
}
