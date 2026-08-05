#include <check.h>

#include "suites.h"
#include "graphics/texture.h"

/*
 * Layer-1 tests for texture.c: sheet lifetimes, sub-rect composition, tile
 * slicing and pixel-to-UV conversion. No GL anywhere — the "GL texture name"
 * is just a number this module carries around, so the tests pick memorable
 * ones (7, 42) and assert they come back out of release.
 */

/* A sheet plus a whole-sheet view, the starting point for most tests below.
 * Created at refs 1 by _create and retained to 2 by _whole; releasing the
 * creator's reference here leaves the view holding the only one, which is what
 * an image handle actually looks like. */
static rgame_texture whole_sheet(unsigned int name, int width, int height) {
    rgame_texture_sheet *sheet = rgame_texture_sheet_create(name, width, height);
    ck_assert_ptr_nonnull(sheet);

    rgame_texture view = rgame_texture_whole(sheet);
    rgame_texture_sheet_release(sheet, NULL);
    return view;
}

static void ck_rect_eq(rgame_rect got, int x, int y, int w, int h) {
    ck_assert_int_eq(got.x, x);
    ck_assert_int_eq(got.y, y);
    ck_assert_int_eq(got.w, w);
    ck_assert_int_eq(got.h, h);
}

/* --- sheet lifetime --- */

START_TEST(a_new_sheet_holds_one_reference_and_dies_on_release) {
    rgame_texture_sheet *sheet = rgame_texture_sheet_create(7, 64, 32);
    ck_assert_ptr_nonnull(sheet);
    ck_assert_int_eq(sheet->width, 64);
    ck_assert_int_eq(sheet->height, 32);

    unsigned int freed = 0;
    ck_assert_int_eq(rgame_texture_sheet_release(sheet, &freed), 1);
    /* The GL name comes back so the caller can delete the texture. */
    ck_assert_uint_eq(freed, 7);
}
END_TEST

START_TEST(a_sheet_with_a_degenerate_size_is_refused) {
    /* An image that decoded to nothing has no valid UV space; a zero divisor
     * downstream is worse than failing here. */
    ck_assert_ptr_null(rgame_texture_sheet_create(1, 0, 32));
    ck_assert_ptr_null(rgame_texture_sheet_create(1, 32, 0));
    ck_assert_ptr_null(rgame_texture_sheet_create(1, -4, -4));
}
END_TEST

START_TEST(a_retained_sheet_survives_a_release) {
    rgame_texture_sheet *sheet = rgame_texture_sheet_create(7, 64, 32);
    rgame_texture_sheet_retain(sheet);

    unsigned int freed = 99;
    ck_assert_int_eq(rgame_texture_sheet_release(sheet, &freed), 0);
    /* Not the last reference, so out_name must be left alone — a caller that
     * deleted on every release would kill a texture other views still use. */
    ck_assert_uint_eq(freed, 99);

    ck_assert_int_eq(rgame_texture_sheet_release(sheet, &freed), 1);
    ck_assert_uint_eq(freed, 7);
}
END_TEST

START_TEST(the_sheet_dies_only_when_the_last_view_goes_in_any_order) {
    rgame_texture_sheet *sheet = rgame_texture_sheet_create(42, 32, 32);
    rgame_texture a = rgame_texture_whole(sheet);
    rgame_texture b = {0};
    rgame_texture c = {0};
    ck_assert_int_eq(rgame_texture_subimage(&a, 0, 0, 16, 16, &b), 1);
    ck_assert_int_eq(rgame_texture_subimage(&b, 0, 0, 8, 8, &c), 1);
    rgame_texture_sheet_release(sheet, NULL); /* the creator lets go */

    /* Drop them out of order: the parent view first, the grandchild last. */
    unsigned int freed = 0;
    ck_assert_int_eq(rgame_texture_destroy(&a, &freed), 0);
    ck_assert_int_eq(rgame_texture_destroy(&b, &freed), 0);
    ck_assert_int_eq(rgame_texture_destroy(&c, &freed), 1);
    ck_assert_uint_eq(freed, 42);
}
END_TEST

START_TEST(destroying_a_view_twice_is_harmless) {
    /* Ruby's GC and an explicit close can both reach the same handle. */
    rgame_texture view = whole_sheet(7, 16, 16);

    unsigned int freed = 0;
    ck_assert_int_eq(rgame_texture_destroy(&view, &freed), 1);
    ck_assert_uint_eq(freed, 7);

    freed = 0;
    ck_assert_int_eq(rgame_texture_destroy(&view, &freed), 0);
    ck_assert_uint_eq(freed, 0);
}
END_TEST

START_TEST(a_clone_is_an_independent_reference_to_the_same_region) {
    rgame_texture view = whole_sheet(7, 64, 64);
    rgame_texture copy = rgame_texture_clone(&view);

    ck_assert_ptr_eq(copy.sheet, view.sheet);
    ck_rect_eq(copy.rect, 0, 0, 64, 64);

    ck_assert_int_eq(rgame_texture_destroy(&view, NULL), 0);
    /* The clone still samples the whole sheet after the original went. */
    ck_assert_int_eq(rgame_texture_width(&copy), 64);
    ck_assert_int_eq(rgame_texture_destroy(&copy, NULL), 1);
}
END_TEST

/* --- subimages --- */

START_TEST(a_whole_sheet_view_covers_the_whole_sheet) {
    rgame_texture view = whole_sheet(7, 64, 32);

    ck_rect_eq(view.rect, 0, 0, 64, 32);
    ck_assert_int_eq(rgame_texture_width(&view), 64);
    ck_assert_int_eq(rgame_texture_height(&view), 32);

    rgame_texture_destroy(&view, NULL);
}
END_TEST

START_TEST(a_subimage_takes_a_region_of_the_sheet) {
    rgame_texture view = whole_sheet(7, 64, 64);
    rgame_texture sub = {0};

    ck_assert_int_eq(rgame_texture_subimage(&view, 16, 8, 32, 24, &sub), 1);
    ck_rect_eq(sub.rect, 16, 8, 32, 24);
    ck_assert_int_eq(rgame_texture_width(&sub), 32);
    ck_assert_int_eq(rgame_texture_height(&sub), 24);
    /* Same upload: a subimage is a view, not a copy. */
    ck_assert_ptr_eq(sub.sheet, view.sheet);

    rgame_texture_destroy(&sub, NULL);
    rgame_texture_destroy(&view, NULL);
}
END_TEST

START_TEST(a_subimage_of_a_subimage_composes_offsets) {
    rgame_texture view = whole_sheet(7, 64, 64);
    rgame_texture sub = {0};
    rgame_texture sub2 = {0};

    ck_assert_int_eq(rgame_texture_subimage(&view, 16, 16, 32, 32, &sub), 1);
    /* 8,4 is relative to `sub`, so it lands at 24,20 on the sheet — the whole
     * point of the coordinates being view-relative. */
    ck_assert_int_eq(rgame_texture_subimage(&sub, 8, 4, 10, 10, &sub2), 1);
    ck_rect_eq(sub2.rect, 24, 20, 10, 10);

    rgame_texture_destroy(&sub2, NULL);
    rgame_texture_destroy(&sub, NULL);
    rgame_texture_destroy(&view, NULL);
}
END_TEST

START_TEST(a_subimage_reaching_outside_its_parent_is_refused) {
    rgame_texture view = whole_sheet(7, 64, 64);
    rgame_texture sub = {0};
    rgame_texture bad = {.rect = {1, 2, 3, 4}};

    ck_assert_int_eq(rgame_texture_subimage(&view, 16, 16, 32, 32, &sub), 1);

    /* Fits on the sheet (48+32 <= 64 fails, but 32+16 would fit at top level)
     * yet reaches past the parent view — which is exactly the indexing bug
     * that otherwise shows up as a sprite with its neighbour's edge on it. */
    ck_assert_int_eq(rgame_texture_subimage(&sub, 16, 0, 32, 8, &bad), 0);
    ck_assert_int_eq(rgame_texture_subimage(&sub, 0, 0, 33, 32, &bad), 0);
    /* And `out` is untouched on refusal. */
    ck_rect_eq(bad.rect, 1, 2, 3, 4);

    rgame_texture_destroy(&sub, NULL);
    rgame_texture_destroy(&view, NULL);
}
END_TEST

START_TEST(a_degenerate_or_negative_subimage_is_refused) {
    rgame_texture view = whole_sheet(7, 64, 64);
    rgame_texture out = {0};

    ck_assert_int_eq(rgame_texture_subimage(&view, 0, 0, 0, 8, &out), 0);
    ck_assert_int_eq(rgame_texture_subimage(&view, 0, 0, 8, 0, &out), 0);
    ck_assert_int_eq(rgame_texture_subimage(&view, -1, 0, 8, 8, &out), 0);
    ck_assert_int_eq(rgame_texture_subimage(&view, 0, -1, 8, 8, &out), 0);
    ck_assert_int_eq(rgame_texture_subimage(&view, 0, 0, -8, -8, &out), 0);

    rgame_texture_destroy(&view, NULL);
}
END_TEST

START_TEST(a_subimage_exactly_filling_its_parent_is_allowed) {
    /* The boundary case: the last tile of a row ends exactly at the edge, so
     * an off-by-one here rejects every sheet's rightmost column. */
    rgame_texture view = whole_sheet(7, 64, 32);
    rgame_texture out = {0};

    ck_assert_int_eq(rgame_texture_subimage(&view, 0, 0, 64, 32, &out), 1);
    ck_rect_eq(out.rect, 0, 0, 64, 32);

    rgame_texture_destroy(&out, NULL);
    rgame_texture_destroy(&view, NULL);
}
END_TEST

/* --- tiles --- */

START_TEST(tile_count_is_whole_tiles_only) {
    rgame_texture view = whole_sheet(7, 64, 32);

    ck_assert_int_eq(rgame_texture_tile_count(&view, 16, 16), 8); /* 4 x 2 */
    ck_assert_int_eq(rgame_texture_tile_count(&view, 64, 32), 1);
    /* 70 does not fit in 64 at all. */
    ck_assert_int_eq(rgame_texture_tile_count(&view, 70, 16), 0);
    /* A partial column at the right edge is padding, not half a sprite. */
    ck_assert_int_eq(rgame_texture_tile_count(&view, 24, 16), 4); /* 2 x 2 */

    rgame_texture_destroy(&view, NULL);
}
END_TEST

START_TEST(a_zero_or_negative_tile_size_yields_no_tiles) {
    /* Rather than dividing by zero, which is how a typo'd tile size would
     * otherwise present. */
    rgame_texture view = whole_sheet(7, 64, 32);

    ck_assert_int_eq(rgame_texture_tile_count(&view, 0, 16), 0);
    ck_assert_int_eq(rgame_texture_tile_count(&view, 16, 0), 0);
    ck_assert_int_eq(rgame_texture_tile_count(&view, -16, -16), 0);

    rgame_texture_destroy(&view, NULL);
}
END_TEST

START_TEST(tiles_are_sliced_row_major) {
    rgame_texture view = whole_sheet(7, 64, 32);
    rgame_texture tile = {0};

    /* 4 columns x 2 rows of 16px tiles. Index 0 is top-left, 3 the end of the
     * first row, 4 the start of the second — the order a sprite sheet's frames
     * are numbered, and the order load_tiles must reproduce. */
    ck_assert_int_eq(rgame_texture_tile(&view, 16, 16, 0, &tile), 1);
    ck_rect_eq(tile.rect, 0, 0, 16, 16);
    rgame_texture_destroy(&tile, NULL);

    ck_assert_int_eq(rgame_texture_tile(&view, 16, 16, 3, &tile), 1);
    ck_rect_eq(tile.rect, 48, 0, 16, 16);
    rgame_texture_destroy(&tile, NULL);

    ck_assert_int_eq(rgame_texture_tile(&view, 16, 16, 4, &tile), 1);
    ck_rect_eq(tile.rect, 0, 16, 16, 16);
    rgame_texture_destroy(&tile, NULL);

    ck_assert_int_eq(rgame_texture_tile(&view, 16, 16, 7, &tile), 1);
    ck_rect_eq(tile.rect, 48, 16, 16, 16);
    rgame_texture_destroy(&tile, NULL);

    rgame_texture_destroy(&view, NULL);
}
END_TEST

START_TEST(an_out_of_range_tile_index_is_refused) {
    rgame_texture view = whole_sheet(7, 64, 32);
    rgame_texture out = {0};

    ck_assert_int_eq(rgame_texture_tile(&view, 16, 16, 8, &out), 0);
    ck_assert_int_eq(rgame_texture_tile(&view, 16, 16, -1, &out), 0);
    ck_assert_int_eq(rgame_texture_tile(&view, 0, 16, 0, &out), 0);
    /* Nothing was retained on the way out. */
    ck_assert_ptr_null(out.sheet);

    rgame_texture_destroy(&view, NULL);
}
END_TEST

START_TEST(tiles_of_a_subimage_are_relative_to_it) {
    /* Slicing the bottom half of a sheet gives tiles from the bottom half. */
    rgame_texture view = whole_sheet(7, 64, 32);
    rgame_texture half = {0};
    rgame_texture tile = {0};
    ck_assert_int_eq(rgame_texture_subimage(&view, 0, 16, 64, 16, &half), 1);

    ck_assert_int_eq(rgame_texture_tile_count(&half, 16, 16), 4);
    ck_assert_int_eq(rgame_texture_tile(&half, 16, 16, 1, &tile), 1);
    ck_rect_eq(tile.rect, 16, 16, 16, 16);

    rgame_texture_destroy(&tile, NULL);
    rgame_texture_destroy(&half, NULL);
    rgame_texture_destroy(&view, NULL);
}
END_TEST

/* --- UVs --- */

START_TEST(a_whole_sheet_spans_the_full_uv_square) {
    rgame_texture view = whole_sheet(7, 64, 32);
    float uv[8] = {0};

    rgame_texture_uv(&view, uv);

    /* Corner order matches the canvas's quad order: TL, TR, BR, BL. */
    ck_assert_float_eq(uv[0], 0.0f); ck_assert_float_eq(uv[1], 0.0f);
    ck_assert_float_eq(uv[2], 1.0f); ck_assert_float_eq(uv[3], 0.0f);
    ck_assert_float_eq(uv[4], 1.0f); ck_assert_float_eq(uv[5], 1.0f);
    ck_assert_float_eq(uv[6], 0.0f); ck_assert_float_eq(uv[7], 1.0f);

    rgame_texture_destroy(&view, NULL);
}
END_TEST

START_TEST(a_subimages_uvs_are_normalised_against_the_sheet) {
    /* The mistake this pins: dividing by the view's own size, which would give
     * every tile the full 0..1 square and draw the same corner everywhere. */
    rgame_texture view = whole_sheet(7, 64, 64);
    rgame_texture sub = {0};
    ck_assert_int_eq(rgame_texture_subimage(&view, 16, 32, 16, 16, &sub), 1);

    float uv[8] = {0};
    rgame_texture_uv(&sub, uv);

    ck_assert_float_eq(uv[0], 0.25f); ck_assert_float_eq(uv[1], 0.5f);
    ck_assert_float_eq(uv[2], 0.5f);  ck_assert_float_eq(uv[3], 0.5f);
    ck_assert_float_eq(uv[4], 0.5f);  ck_assert_float_eq(uv[5], 0.75f);
    ck_assert_float_eq(uv[6], 0.25f); ck_assert_float_eq(uv[7], 0.75f);

    rgame_texture_destroy(&sub, NULL);
    rgame_texture_destroy(&view, NULL);
}
END_TEST

START_TEST(v_increases_downwards) {
    /* The top half of a sheet is v 0..0.5, not 0.5..1. Getting this backwards
     * flips every sprite vertically, and a symmetric test sprite hides it. */
    rgame_texture view = whole_sheet(7, 32, 32);
    rgame_texture top = {0};
    ck_assert_int_eq(rgame_texture_subimage(&view, 0, 0, 32, 16, &top), 1);

    float uv[8] = {0};
    rgame_texture_uv(&top, uv);

    ck_assert_float_eq(uv[1], 0.0f); /* top edge */
    ck_assert_float_eq(uv[5], 0.5f); /* bottom edge */

    rgame_texture_destroy(&top, NULL);
    rgame_texture_destroy(&view, NULL);
}
END_TEST

START_TEST(a_non_square_sheet_normalises_each_axis_by_its_own_size) {
    /* One shared divisor would put a square tile's UVs on a rectangle. */
    rgame_texture view = whole_sheet(7, 100, 50);
    rgame_texture sub = {0};
    ck_assert_int_eq(rgame_texture_subimage(&view, 25, 25, 25, 25, &sub), 1);

    float uv[8] = {0};
    rgame_texture_uv(&sub, uv);

    ck_assert_float_eq(uv[0], 0.25f); /* 25/100 */
    ck_assert_float_eq(uv[1], 0.5f);  /* 25/50 */
    ck_assert_float_eq(uv[4], 0.5f);  /* 50/100 */
    ck_assert_float_eq(uv[5], 1.0f);  /* 50/50 */

    rgame_texture_destroy(&sub, NULL);
    rgame_texture_destroy(&view, NULL);
}
END_TEST

START_TEST(an_empty_view_has_no_size_and_degenerate_uvs) {
    rgame_texture empty = {0};
    float uv[8] = {9, 9, 9, 9, 9, 9, 9, 9};

    ck_assert_int_eq(rgame_texture_width(&empty), 0);
    ck_assert_int_eq(rgame_texture_height(&empty), 0);
    ck_assert_int_eq(rgame_texture_tile_count(&empty, 16, 16), 0);

    /* No sheet means no size to divide by; zeros beat a NaN reaching the GPU. */
    rgame_texture_uv(&empty, uv);
    for (int i = 0; i < 8; i++) {
        ck_assert_float_eq(uv[i], 0.0f);
    }
}
END_TEST

START_TEST(the_live_sheet_count_follows_the_last_reference) {
    /* The counter Ruby's specs assert against, checked here where the whole
     * lifetime is visible in one place. */
    long before = rgame_texture_live_sheets();

    rgame_texture view = whole_sheet(7, 32, 32);
    ck_assert_int_eq(rgame_texture_live_sheets(), before + 1);

    rgame_texture tile = {0};
    ck_assert_int_eq(rgame_texture_tile(&view, 16, 16, 0, &tile), 1);
    /* A tile is a view of the same upload, not a second one. */
    ck_assert_int_eq(rgame_texture_live_sheets(), before + 1);

    rgame_texture_destroy(&view, NULL);
    ck_assert_int_eq(rgame_texture_live_sheets(), before + 1);

    rgame_texture_destroy(&tile, NULL);
    ck_assert_int_eq(rgame_texture_live_sheets(), before);
}
END_TEST

Suite *texture_suite(void) {
    Suite *suite = suite_create("texture");
    TCase *tc = tcase_create("core");

    tcase_add_test(tc, a_new_sheet_holds_one_reference_and_dies_on_release);
    tcase_add_test(tc, a_sheet_with_a_degenerate_size_is_refused);
    tcase_add_test(tc, a_retained_sheet_survives_a_release);
    tcase_add_test(tc, the_sheet_dies_only_when_the_last_view_goes_in_any_order);
    tcase_add_test(tc, destroying_a_view_twice_is_harmless);
    tcase_add_test(tc, a_clone_is_an_independent_reference_to_the_same_region);

    tcase_add_test(tc, a_whole_sheet_view_covers_the_whole_sheet);
    tcase_add_test(tc, a_subimage_takes_a_region_of_the_sheet);
    tcase_add_test(tc, a_subimage_of_a_subimage_composes_offsets);
    tcase_add_test(tc, a_subimage_reaching_outside_its_parent_is_refused);
    tcase_add_test(tc, a_degenerate_or_negative_subimage_is_refused);
    tcase_add_test(tc, a_subimage_exactly_filling_its_parent_is_allowed);

    tcase_add_test(tc, tile_count_is_whole_tiles_only);
    tcase_add_test(tc, a_zero_or_negative_tile_size_yields_no_tiles);
    tcase_add_test(tc, tiles_are_sliced_row_major);
    tcase_add_test(tc, an_out_of_range_tile_index_is_refused);
    tcase_add_test(tc, tiles_of_a_subimage_are_relative_to_it);

    tcase_add_test(tc, a_whole_sheet_spans_the_full_uv_square);
    tcase_add_test(tc, a_subimages_uvs_are_normalised_against_the_sheet);
    tcase_add_test(tc, v_increases_downwards);
    tcase_add_test(tc, a_non_square_sheet_normalises_each_axis_by_its_own_size);
    tcase_add_test(tc, an_empty_view_has_no_size_and_degenerate_uvs);
    tcase_add_test(tc, the_live_sheet_count_follows_the_last_reference);

    suite_add_tcase(suite, tc);
    return suite;
}
