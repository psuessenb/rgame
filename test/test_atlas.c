#include <check.h>

#include "text/atlas.h"
#include "suites.h"

/*
 * Layer-1 tests for atlas.c: where each glyph lands on a page, when a new shelf
 * opens, and when the page is full. Pure integer arithmetic, so every
 * expectation below is an exact rectangle rather than a tolerance.
 */

static void ck_rect_eq(rgame_rect got, int x, int y, int w, int h) {
    ck_assert_int_eq(got.x, x);
    ck_assert_int_eq(got.y, y);
    ck_assert_int_eq(got.w, w);
    ck_assert_int_eq(got.h, h);
}

/* Places a glyph that is expected to fit, and returns where it went. */
static rgame_rect place(rgame_atlas *atlas, int width, int height) {
    rgame_rect out = { -1, -1, -1, -1 };
    ck_assert_int_eq(rgame_atlas_place(atlas, width, height, &out), 1);
    return out;
}

static int overlaps(rgame_rect a, rgame_rect b) {
    return !rgame_rect_is_empty(rgame_rect_intersect(a, b));
}

/* --- filling a shelf --- */

START_TEST(the_first_glyph_lands_at_the_origin) {
    rgame_atlas atlas;
    rgame_atlas_init(&atlas, 64, 64);

    ck_rect_eq(place(&atlas, 10, 12), 0, 0, 10, 12);
}
END_TEST

START_TEST(the_next_glyph_sits_to_the_right_with_a_gutter_between) {
    /* One pixel of clear space, because the atlas is sampled with linear
     * filtering and a glyph packed flush bleeds into its neighbour. */
    rgame_atlas atlas;
    rgame_atlas_init(&atlas, 64, 64);

    place(&atlas, 10, 12);
    ck_rect_eq(place(&atlas, 8, 12), 10 + RGAME_ATLAS_GUTTER, 0, 8, 12);
}
END_TEST

START_TEST(a_shelf_fills_left_to_right) {
    rgame_atlas atlas;
    rgame_atlas_init(&atlas, 64, 64);

    ck_rect_eq(place(&atlas, 5, 5), 0, 0, 5, 5);
    ck_rect_eq(place(&atlas, 5, 5), 6, 0, 5, 5);
    ck_rect_eq(place(&atlas, 5, 5), 12, 0, 5, 5);
}
END_TEST

/* --- opening the next shelf --- */

START_TEST(a_glyph_that_does_not_fit_the_row_starts_a_new_shelf) {
    rgame_atlas atlas;
    rgame_atlas_init(&atlas, 20, 64);

    place(&atlas, 12, 8);
    /* 12 + gutter + 12 is past 20, so this drops to the next row. */
    ck_rect_eq(place(&atlas, 12, 8), 0, 8 + RGAME_ATLAS_GUTTER, 12, 8);
}
END_TEST

START_TEST(the_new_shelf_clears_the_tallest_glyph_on_the_old_one) {
    /* The trap: dropping below the *last* glyph rather than the tallest. Here
     * the tall glyph comes first and a short one follows, so a packer that
     * measured the last one would overlap the tall one's bottom half. */
    rgame_atlas atlas;
    rgame_atlas_init(&atlas, 20, 64);

    rgame_rect tall = place(&atlas, 9, 20);
    place(&atlas, 9, 3);

    rgame_rect next_shelf = place(&atlas, 9, 5);
    ck_assert_int_eq(next_shelf.y, 20 + RGAME_ATLAS_GUTTER);
    ck_assert_int_eq(overlaps(tall, next_shelf), 0);
}
END_TEST

START_TEST(each_shelf_measures_only_its_own_glyphs) {
    /* shelf_height has to reset when a shelf does, or every later shelf keeps
     * paying for the tallest glyph on the whole page. */
    rgame_atlas atlas;
    rgame_atlas_init(&atlas, 20, 128);

    place(&atlas, 18, 30); /* shelf 0, tall */
    place(&atlas, 18, 4);  /* shelf 1, short */
    ck_rect_eq(place(&atlas, 18, 4), 0, 30 + 1 + 4 + 1, 18, 4); /* shelf 2 */
}
END_TEST

/* --- running out --- */

START_TEST(a_full_page_is_refused_rather_than_overflowing) {
    rgame_atlas atlas;
    rgame_atlas_init(&atlas, 16, 16);

    place(&atlas, 16, 10);

    rgame_rect out = { -1, -1, -1, -1 };
    /* Only 5 rows are left below the gutter, so an 8-tall glyph cannot go. */
    ck_assert_int_eq(rgame_atlas_place(&atlas, 16, 8, &out), 0);
    /* And `out` is untouched, so a caller that ignores the return value gets a
     * stale rectangle rather than one pointing off the page. */
    ck_rect_eq(out, -1, -1, -1, -1);
}
END_TEST

START_TEST(a_shelf_that_would_end_one_row_past_the_bottom_is_refused) {
    /* The off-by-one that only shows on the *last* shelf: with `>=` instead of
     * `>` the page loses its bottom row, and with `> height + 1` a glyph hangs
     * one row off the end of the texture. Both need a shelf that starts part
     * way down, which the "full page" case above does not produce. */
    rgame_atlas atlas;
    rgame_atlas_init(&atlas, 16, 16);

    place(&atlas, 16, 8); /* shelf 0 occupies rows 0..7, so shelf 1 starts at 9 */

    rgame_rect out = { -1, -1, -1, -1 };
    /* 9 + 8 is 17, one row past a 16-row page. */
    ck_assert_int_eq(rgame_atlas_place(&atlas, 16, 8, &out), 0);
    ck_rect_eq(out, -1, -1, -1, -1);

    /* ...but 7 rows do fit, exactly. */
    ck_rect_eq(place(&atlas, 16, 7), 0, 9, 16, 7);
}
END_TEST

START_TEST(refusing_an_oversized_glyph_does_not_disturb_the_shelf) {
    /* An over-tall glyph is refused either way — the page-height check below
     * would catch it. What the early guard prevents is the *shelf move* on the
     * way there: without it, a glyph that is both too tall and too wide for the
     * remaining row opens a fresh shelf before failing, and the next glyph that
     * would have fitted the current row lands a row lower for no reason. */
    rgame_atlas atlas;
    rgame_atlas_init(&atlas, 32, 64);

    place(&atlas, 20, 10);

    rgame_rect out = { 0 };
    ck_assert_int_eq(rgame_atlas_place(&atlas, 30, 90, &out), 0);

    /* Still on the first shelf, right where it was. */
    ck_rect_eq(place(&atlas, 8, 10), 21, 0, 8, 10);
}
END_TEST

START_TEST(a_glyph_bigger_than_the_page_is_refused) {
    /* Refused immediately rather than after opening a shelf it can never fill:
     * a page that keeps shelving for a glyph that will never fit would walk off
     * the bottom one row at a time. */
    rgame_atlas atlas;
    rgame_atlas_init(&atlas, 32, 32);

    rgame_rect out = { 0 };
    ck_assert_int_eq(rgame_atlas_place(&atlas, 40, 8, &out), 0);
    ck_assert_int_eq(rgame_atlas_place(&atlas, 8, 40, &out), 0);
    ck_assert_int_eq(rgame_atlas_place(&atlas, 40, 40, &out), 0);

    /* ...and the page is still usable afterwards. A refusal is an ordinary
     * answer, not damage. */
    ck_rect_eq(place(&atlas, 8, 8), 0, 0, 8, 8);
}
END_TEST

START_TEST(a_glyph_exactly_the_size_of_the_page_fits) {
    /* The boundary: an off-by-one here rejects the largest glyph a page can
     * actually hold, which is the one most likely to be a capital letter. */
    rgame_atlas atlas;
    rgame_atlas_init(&atlas, 32, 32);

    ck_rect_eq(place(&atlas, 32, 32), 0, 0, 32, 32);
}
END_TEST

START_TEST(a_row_that_ends_exactly_at_the_edge_fits) {
    rgame_atlas atlas;
    rgame_atlas_init(&atlas, 21, 64);

    ck_rect_eq(place(&atlas, 10, 8), 0, 0, 10, 8);
    /* 11 + 10 == 21, the full width, with the gutter already spent. */
    ck_rect_eq(place(&atlas, 10, 8), 11, 0, 10, 8);
}
END_TEST

START_TEST(a_degenerate_page_refuses_everything) {
    rgame_atlas atlas;
    rgame_atlas_init(&atlas, 0, 0);

    rgame_rect out = { 0 };
    ck_assert_int_eq(rgame_atlas_place(&atlas, 1, 1, &out), 0);
}
END_TEST

START_TEST(a_negative_page_size_becomes_zero_not_negative) {
    /* The size is read back by the layer that allocates the texture behind the
     * page, so it has to be a size — a negative one there is an allocation
     * nobody checks. */
    rgame_atlas atlas;
    rgame_atlas_init(&atlas, -8, -4);

    ck_assert_int_eq(atlas.width, 0);
    ck_assert_int_eq(atlas.height, 0);

    rgame_rect out = { 0 };
    ck_assert_int_eq(rgame_atlas_place(&atlas, 1, 1, &out), 0);
}
END_TEST

/* --- glyphs with no pixels --- */

START_TEST(a_glyph_with_no_pixels_succeeds_and_reserves_nothing) {
    /* The space character rasterises to an empty bitmap but still has an
     * advance. Handling it here means the font layer has no special case to
     * remember. */
    rgame_atlas atlas;
    rgame_atlas_init(&atlas, 64, 64);

    place(&atlas, 10, 10);

    rgame_rect empty = place(&atlas, 0, 0);
    ck_assert_int_eq(empty.w, 0);
    ck_assert_int_eq(empty.h, 0);

    /* The next real glyph goes where it would have gone anyway. */
    ck_rect_eq(place(&atlas, 10, 10), 11, 0, 10, 10);
}
END_TEST

START_TEST(a_negative_size_is_treated_as_no_pixels) {
    rgame_atlas atlas;
    rgame_atlas_init(&atlas, 64, 64);

    rgame_rect out = { 0 };
    ck_assert_int_eq(rgame_atlas_place(&atlas, -5, 10, &out), 1);
    ck_assert_int_eq(out.w, 0);
    ck_assert_int_eq(rgame_atlas_place(&atlas, 10, -5, &out), 1);
    ck_assert_int_eq(out.h, 0);

    ck_rect_eq(place(&atlas, 4, 4), 0, 0, 4, 4);
}
END_TEST

/* --- the property that matters --- */

START_TEST(no_two_placements_ever_overlap) {
    /*
     * Every assertion above checks one arrangement. This checks the invariant
     * the whole module exists for, across a page's worth of varied glyph sizes:
     * two glyphs sharing a pixel means one of them draws part of the other, for
     * the rest of the program's life.
     *
     * The sizes are deterministic but irregular, so shelves break at awkward
     * places rather than lining up.
     */
    rgame_atlas atlas;
    rgame_atlas_init(&atlas, 128, 128);

    rgame_rect placed[256];
    int count = 0;

    for (int i = 0; i < 256; i++) {
        int width = 3 + ((i * 7) % 17);
        int height = 4 + ((i * 5) % 11);

        rgame_rect out;
        if (!rgame_atlas_place(&atlas, width, height, &out)) {
            break; /* page full, which is the expected end */
        }

        /* On the page... */
        ck_assert_int_ge(out.x, 0);
        ck_assert_int_ge(out.y, 0);
        ck_assert_int_le(out.x + out.w, atlas.width);
        ck_assert_int_le(out.y + out.h, atlas.height);
        /* ...the size asked for... */
        ck_assert_int_eq(out.w, width);
        ck_assert_int_eq(out.h, height);
        /* ...and clear of everything before it. */
        for (int j = 0; j < count; j++) {
            ck_assert_int_eq(overlaps(placed[j], out), 0);
        }

        placed[count++] = out;
    }

    /* A 128x128 page should swallow a good many glyphs of this size before
     * filling; if it stopped after a handful, the shelf logic is wasting most
     * of the page and the overlap check above proved very little. */
    ck_assert_int_gt(count, 60);
}
END_TEST

Suite *atlas_suite(void) {
    Suite *suite = suite_create("atlas");
    TCase *tc = tcase_create("core");

    tcase_add_test(tc, the_first_glyph_lands_at_the_origin);
    tcase_add_test(tc, the_next_glyph_sits_to_the_right_with_a_gutter_between);
    tcase_add_test(tc, a_shelf_fills_left_to_right);

    tcase_add_test(tc, a_glyph_that_does_not_fit_the_row_starts_a_new_shelf);
    tcase_add_test(tc, the_new_shelf_clears_the_tallest_glyph_on_the_old_one);
    tcase_add_test(tc, each_shelf_measures_only_its_own_glyphs);

    tcase_add_test(tc, a_full_page_is_refused_rather_than_overflowing);
    tcase_add_test(tc, a_shelf_that_would_end_one_row_past_the_bottom_is_refused);
    tcase_add_test(tc, refusing_an_oversized_glyph_does_not_disturb_the_shelf);
    tcase_add_test(tc, a_glyph_bigger_than_the_page_is_refused);
    tcase_add_test(tc, a_glyph_exactly_the_size_of_the_page_fits);
    tcase_add_test(tc, a_row_that_ends_exactly_at_the_edge_fits);
    tcase_add_test(tc, a_degenerate_page_refuses_everything);
    tcase_add_test(tc, a_negative_page_size_becomes_zero_not_negative);

    tcase_add_test(tc, a_glyph_with_no_pixels_succeeds_and_reserves_nothing);
    tcase_add_test(tc, a_negative_size_is_treated_as_no_pixels);

    tcase_add_test(tc, no_two_placements_ever_overlap);

    suite_add_tcase(suite, tc);
    return suite;
}
