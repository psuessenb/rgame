#include <check.h>

#include "text/glyph_cache.h"
#include "suites.h"

/*
 * Layer-1 tests for glyph_cache.c. No font and no GL — a cached glyph is a
 * codepoint, a rectangle and three numbers, and everything worth checking is
 * about whether the table hands the right one back.
 */

/* A glyph whose every field is derived from its codepoint, so a round-trip that
 * loses or swaps a field is visible rather than plausible. */
static rgame_glyph glyph_for(int codepoint) {
    rgame_glyph glyph = {
        .codepoint = codepoint,
        .page = codepoint % 3,
        .rect = rgame_rect_make(codepoint, codepoint + 1, codepoint + 2, codepoint + 3),
        .advance = (float)codepoint * 0.5f,
        .bearing_x = (float)codepoint * 0.25f,
        .bearing_y = (float)codepoint * -0.125f,
    };
    return glyph;
}

static void ck_glyph_eq(rgame_glyph got, rgame_glyph want) {
    ck_assert_int_eq(got.codepoint, want.codepoint);
    ck_assert_int_eq(got.page, want.page);
    ck_assert_int_eq(got.rect.x, want.rect.x);
    ck_assert_int_eq(got.rect.y, want.rect.y);
    ck_assert_int_eq(got.rect.w, want.rect.w);
    ck_assert_int_eq(got.rect.h, want.rect.h);
    ck_assert_float_eq(got.advance, want.advance);
    ck_assert_float_eq(got.bearing_x, want.bearing_x);
    ck_assert_float_eq(got.bearing_y, want.bearing_y);
}

/* --- an empty cache --- */

START_TEST(a_fresh_cache_holds_nothing_and_has_allocated_nothing) {
    rgame_glyph_cache cache;
    rgame_glyph_cache_init(&cache);

    ck_assert_uint_eq(rgame_glyph_cache_count(&cache), 0);
    /* A font that never draws text should cost nothing but the struct. */
    ck_assert_ptr_null(cache.entries);

    rgame_glyph out = glyph_for(999);
    ck_assert_int_eq(rgame_glyph_cache_find(&cache, 'a', &out), 0);
    /* A miss leaves the caller's glyph alone rather than half-filling it. */
    ck_assert_int_eq(out.codepoint, 999);

    rgame_glyph_cache_destroy(&cache);
}
END_TEST

START_TEST(destroying_a_cache_twice_is_harmless) {
    rgame_glyph_cache cache;
    rgame_glyph_cache_init(&cache);
    rgame_glyph inserted = glyph_for('a');
    rgame_glyph_cache_insert(&cache, &inserted);

    rgame_glyph_cache_destroy(&cache);
    rgame_glyph_cache_destroy(&cache);

    /* And it is an empty cache again, not a broken one. */
    rgame_glyph out;
    ck_assert_int_eq(rgame_glyph_cache_find(&cache, 'a', &out), 0);
    ck_assert_uint_eq(rgame_glyph_cache_count(&cache), 0);
}
END_TEST

/* --- round-tripping --- */

START_TEST(an_inserted_glyph_comes_back_intact) {
    rgame_glyph_cache cache;
    rgame_glyph_cache_init(&cache);

    rgame_glyph inserted = glyph_for('A');
    ck_assert_int_eq(rgame_glyph_cache_insert(&cache, &inserted), 1);

    rgame_glyph out;
    ck_assert_int_eq(rgame_glyph_cache_find(&cache, 'A', &out), 1);
    ck_glyph_eq(out, inserted);

    rgame_glyph_cache_destroy(&cache);
}
END_TEST

START_TEST(a_glyph_with_no_ink_is_cached_too) {
    /* A space has an empty rectangle but a real advance, and caching it is the
     * point — otherwise every space in every string re-measures. */
    rgame_glyph_cache cache;
    rgame_glyph_cache_init(&cache);

    rgame_glyph space = { .codepoint = ' ', .rect = rgame_rect_make(0, 0, 0, 0),
                          .advance = 4.5f };
    rgame_glyph_cache_insert(&cache, &space);

    rgame_glyph out;
    ck_assert_int_eq(rgame_glyph_cache_find(&cache, ' ', &out), 1);
    ck_assert_float_eq(out.advance, 4.5f);
    ck_assert_int_eq(out.rect.w, 0);

    rgame_glyph_cache_destroy(&cache);
}
END_TEST

START_TEST(codepoints_beyond_ascii_round_trip) {
    /* The whole reason the key is a codepoint and not a byte. */
    rgame_glyph_cache cache;
    rgame_glyph_cache_init(&cache);

    const int codepoints[] = { 0xE4 /* a-umlaut */, 0xDF /* sharp s */, 0x20AC /* euro */,
                               0x1E9E /* capital sharp s */, 0x1F600 /* an emoji */ };

    for (unsigned i = 0; i < sizeof(codepoints) / sizeof(*codepoints); i++) {
        rgame_glyph glyph = glyph_for(codepoints[i]);
        ck_assert_int_eq(rgame_glyph_cache_insert(&cache, &glyph), 1);
    }

    for (unsigned i = 0; i < sizeof(codepoints) / sizeof(*codepoints); i++) {
        rgame_glyph out;
        ck_assert_int_eq(rgame_glyph_cache_find(&cache, codepoints[i], &out), 1);
        ck_glyph_eq(out, glyph_for(codepoints[i]));
    }

    rgame_glyph_cache_destroy(&cache);
}
END_TEST

START_TEST(codepoint_zero_is_refused) {
    /* 0 is the empty-slot marker. Storing it would write an entry that find can
     * never see, and would throw the count off by one forever. */
    rgame_glyph_cache cache;
    rgame_glyph_cache_init(&cache);

    rgame_glyph zero = glyph_for(0);
    ck_assert_int_eq(rgame_glyph_cache_insert(&cache, &zero), 0);
    ck_assert_uint_eq(rgame_glyph_cache_count(&cache), 0);

    rgame_glyph out;
    ck_assert_int_eq(rgame_glyph_cache_find(&cache, 0, &out), 0);

    rgame_glyph_cache_destroy(&cache);
}
END_TEST

/* --- counting --- */

START_TEST(the_count_tracks_distinct_codepoints_not_calls) {
    /* The property the design rests on: drawing "aaaa" every frame forever must
     * not grow the cache. */
    rgame_glyph_cache cache;
    rgame_glyph_cache_init(&cache);

    for (int i = 0; i < 100; i++) {
        rgame_glyph glyph = glyph_for('a');
        rgame_glyph_cache_insert(&cache, &glyph);
    }

    ck_assert_uint_eq(rgame_glyph_cache_count(&cache), 1);

    rgame_glyph_cache_destroy(&cache);
}
END_TEST

START_TEST(reinserting_a_codepoint_replaces_it) {
    rgame_glyph_cache cache;
    rgame_glyph_cache_init(&cache);

    rgame_glyph first = glyph_for('a');
    rgame_glyph_cache_insert(&cache, &first);

    /* Same codepoint, moved to another page — what re-uploading a glyph looks
     * like. The old entry must go, not linger behind the new one. */
    rgame_glyph moved = glyph_for('a');
    moved.page = 7;
    moved.rect = rgame_rect_make(100, 200, 8, 9);
    rgame_glyph_cache_insert(&cache, &moved);

    rgame_glyph out;
    ck_assert_int_eq(rgame_glyph_cache_find(&cache, 'a', &out), 1);
    ck_assert_int_eq(out.page, 7);
    ck_assert_int_eq(out.rect.x, 100);
    ck_assert_uint_eq(rgame_glyph_cache_count(&cache), 1);

    rgame_glyph_cache_destroy(&cache);
}
END_TEST

/* --- collisions and growth --- */

START_TEST(keys_that_collide_are_all_still_retrievable) {
    /*
     * The keys are a realistic character set — letters, digits, punctuation,
     * accents — and that is the whole point of the test.
     *
     * An earlier version used an arithmetic progression (i * 37) on the theory
     * that crowding the table would produce collisions. It produced *none*: a
     * multiplicative hash with an odd multiplier maps an arithmetic progression
     * to distinct slots, so the test exercised no probe walk whatsoever and let
     * a broken wrap-around through. What a font actually gets asked for is
     * irregular, and irregular keys collide — measurably, ten times over for
     * the set below in a fresh table.
     */
    static const char ASCII[] = "abcdefghijklmnopqrstuvwxyz"
                                "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
                                "0123456789 .,:;!?'\"()[]-+*/=%#@&";
    static const int ACCENTED[] = { 0xE4, 0xF6, 0xFC, 0xDF, 0xE9, 0xE8, 0xEA, 0xF1,
                                    0xE7, 0x20AC, 0x2013, 0x201C, 0x201D };

    rgame_glyph_cache cache;
    rgame_glyph_cache_init(&cache);

    for (const char *c = ASCII; *c; c++) {
        rgame_glyph glyph = glyph_for((unsigned char)*c);
        ck_assert_int_eq(rgame_glyph_cache_insert(&cache, &glyph), 1);
    }
    for (unsigned i = 0; i < sizeof(ACCENTED) / sizeof(*ACCENTED); i++) {
        rgame_glyph glyph = glyph_for(ACCENTED[i]);
        ck_assert_int_eq(rgame_glyph_cache_insert(&cache, &glyph), 1);
    }

    for (const char *c = ASCII; *c; c++) {
        rgame_glyph out;
        ck_assert_int_eq(rgame_glyph_cache_find(&cache, (unsigned char)*c, &out), 1);
        ck_glyph_eq(out, glyph_for((unsigned char)*c));
    }
    for (unsigned i = 0; i < sizeof(ACCENTED) / sizeof(*ACCENTED); i++) {
        rgame_glyph out;
        ck_assert_int_eq(rgame_glyph_cache_find(&cache, ACCENTED[i], &out), 1);
        ck_glyph_eq(out, glyph_for(ACCENTED[i]));
    }

    rgame_glyph_cache_destroy(&cache);
}
END_TEST

START_TEST(a_missing_codepoint_that_probes_past_a_collision_still_misses) {
    /* Linear probing walks past occupied slots. A find that stopped at the
     * first non-matching entry would report a miss for a glyph that is there;
     * one that walked past the first *empty* slot would scan the whole table
     * for every miss. This checks the miss case around a real collision. */
    rgame_glyph_cache cache;
    rgame_glyph_cache_init(&cache);

    for (int codepoint = 'a'; codepoint <= 'z'; codepoint++) {
        rgame_glyph glyph = glyph_for(codepoint);
        rgame_glyph_cache_insert(&cache, &glyph);
    }

    rgame_glyph out;
    ck_assert_int_eq(rgame_glyph_cache_find(&cache, 'A', &out), 0);
    ck_assert_int_eq(rgame_glyph_cache_find(&cache, 0x20AC, &out), 0);
    /* Every inserted one is still findable. */
    for (int codepoint = 'a'; codepoint <= 'z'; codepoint++) {
        ck_assert_int_eq(rgame_glyph_cache_find(&cache, codepoint, &out), 1);
        ck_glyph_eq(out, glyph_for(codepoint));
    }

    rgame_glyph_cache_destroy(&cache);
}
END_TEST

START_TEST(a_miss_on_a_populated_cache_leaves_the_caller_alone) {
    /* The empty-cache miss above returns before the table is ever touched, so
     * it says nothing about this path: a find that copied the slot out *before*
     * checking whether it matched would hand back a neighbouring glyph, and the
     * caller — which is about to draw with it — has no way to tell. */
    rgame_glyph_cache cache;
    rgame_glyph_cache_init(&cache);

    for (int codepoint = 'a'; codepoint <= 'z'; codepoint++) {
        rgame_glyph glyph = glyph_for(codepoint);
        rgame_glyph_cache_insert(&cache, &glyph);
    }

    rgame_glyph out = glyph_for(999);
    ck_assert_int_eq(rgame_glyph_cache_find(&cache, 'Z', &out), 0);
    ck_glyph_eq(out, glyph_for(999));

    rgame_glyph_cache_destroy(&cache);
}
END_TEST

START_TEST(the_table_grows_without_losing_anything) {
    /*
     * Enough codepoints to force several rehashes. Every one has to survive
     * every rehash: a growth that dropped entries would look like a cache miss,
     * which is invisible — the glyph would simply be rasterised again, a little
     * slower, forever.
     */
    const int count = 2000;
    rgame_glyph_cache cache;
    rgame_glyph_cache_init(&cache);

    for (int i = 1; i <= count; i++) {
        rgame_glyph glyph = glyph_for(i);
        ck_assert_int_eq(rgame_glyph_cache_insert(&cache, &glyph), 1);
    }

    ck_assert_uint_eq(rgame_glyph_cache_count(&cache), (unsigned int)count);
    for (int i = 1; i <= count; i++) {
        rgame_glyph out;
        ck_assert_int_eq(rgame_glyph_cache_find(&cache, i, &out), 1);
        ck_glyph_eq(out, glyph_for(i));
    }

    /* And it grew rather than filling: a table at capacity would make every
     * miss a full scan, and the probe loop has no other way out. */
    ck_assert_uint_gt(cache.capacity, cache.count);

    rgame_glyph_cache_destroy(&cache);
}
END_TEST

START_TEST(growth_keeps_the_table_loose_enough_to_probe) {
    /* Linear probing turns into a linear scan as a table approaches full, so
     * the load factor is a correctness-adjacent property, not a tuning knob:
     * the probe walk relies on an empty slot always existing. */
    rgame_glyph_cache cache;
    rgame_glyph_cache_init(&cache);

    for (int i = 1; i <= 500; i++) {
        rgame_glyph glyph = glyph_for(i);
        rgame_glyph_cache_insert(&cache, &glyph);
        ck_assert_uint_lt(cache.count, cache.capacity);
        ck_assert_uint_le(cache.count * 4, cache.capacity * 3);
    }

    rgame_glyph_cache_destroy(&cache);
}
END_TEST

Suite *glyph_cache_suite(void) {
    Suite *suite = suite_create("glyph_cache");
    TCase *tc = tcase_create("core");

    tcase_add_test(tc, a_fresh_cache_holds_nothing_and_has_allocated_nothing);
    tcase_add_test(tc, destroying_a_cache_twice_is_harmless);

    tcase_add_test(tc, an_inserted_glyph_comes_back_intact);
    tcase_add_test(tc, a_glyph_with_no_ink_is_cached_too);
    tcase_add_test(tc, codepoints_beyond_ascii_round_trip);
    tcase_add_test(tc, codepoint_zero_is_refused);

    tcase_add_test(tc, the_count_tracks_distinct_codepoints_not_calls);
    tcase_add_test(tc, reinserting_a_codepoint_replaces_it);

    tcase_add_test(tc, keys_that_collide_are_all_still_retrievable);
    tcase_add_test(tc, a_missing_codepoint_that_probes_past_a_collision_still_misses);
    tcase_add_test(tc, a_miss_on_a_populated_cache_leaves_the_caller_alone);
    tcase_add_test(tc, the_table_grows_without_losing_anything);
    tcase_add_test(tc, growth_keeps_the_table_loose_enough_to_probe);

    suite_add_tcase(suite, tc);
    return suite;
}
