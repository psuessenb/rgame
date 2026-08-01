#include <check.h>

#include "device_slots.h"
#include "suites.h"

/*
 * Every decision in device_slots.c is exercised here with no SDL and no
 * hardware — plugging controllers in and out by hand is exactly the kind of
 * verification this module exists to avoid.
 */

/* A distinct GUID per *model*. Real SDL GUIDs identify a model, not a unit, so
 * two identical pads share one — which is why pad_a/pad_a appears below. */
static rgame_device_guid guid_of(unsigned char tag) {
    rgame_device_guid guid;
    for (int i = 0; i < RGAME_DEVICE_GUID_BYTES; i++) {
        guid.bytes[i] = (unsigned char)(tag + i);
    }
    return guid;
}

START_TEST(init_leaves_every_slot_empty) {
    rgame_device_slots table;
    rgame_device_slots_init(&table);

    ck_assert_int_eq(rgame_device_slots_count(&table), 0);
    for (int i = 0; i < RGAME_MAX_DEVICE_SLOTS; i++) {
        ck_assert_int_eq(rgame_device_slots_connected(&table, i), 0);
        ck_assert_int_eq(rgame_device_slots_instance_id(&table, i), RGAME_DEVICE_SLOT_NONE);
    }
}
END_TEST

START_TEST(slots_fill_lowest_first) {
    rgame_device_slots table;
    rgame_device_slots_init(&table);

    rgame_device_guid a = guid_of(0x10);
    rgame_device_guid b = guid_of(0x20);
    rgame_device_guid c = guid_of(0x30);

    ck_assert_int_eq(rgame_device_slots_connect(&table, &a, 101), 0);
    ck_assert_int_eq(rgame_device_slots_connect(&table, &b, 102), 1);
    ck_assert_int_eq(rgame_device_slots_connect(&table, &c, 103), 2);
    ck_assert_int_eq(rgame_device_slots_count(&table), 3);
}
END_TEST

START_TEST(reconnecting_the_same_pad_reclaims_its_slot) {
    rgame_device_slots table;
    rgame_device_slots_init(&table);

    rgame_device_guid a = guid_of(0x10);
    rgame_device_guid b = guid_of(0x20);
    rgame_device_guid c = guid_of(0x30);

    ck_assert_int_eq(rgame_device_slots_connect(&table, &a, 101), 0);
    ck_assert_int_eq(rgame_device_slots_connect(&table, &b, 102), 1);
    ck_assert_int_eq(rgame_device_slots_connect(&table, &c, 103), 2);

    /*
     * Free slots 0 AND 1, then bring pad B back. Slot 1 is deliberately not
     * the lowest free slot: if this only asserted on a single disconnect, a
     * table that had forgotten the GUID entirely would still answer "slot 0"
     * and the test would pass for the wrong reason. Demanding slot 1 is what
     * actually pins the reclaim-by-GUID behaviour.
     */
    ck_assert_int_eq(rgame_device_slots_disconnect(&table, 101), 0);
    ck_assert_int_eq(rgame_device_slots_disconnect(&table, 102), 1);
    ck_assert_int_eq(rgame_device_slots_count(&table), 1);

    /* Back with a brand new instance id, as SDL would report it. */
    ck_assert_int_eq(rgame_device_slots_connect(&table, &b, 999), 1);
    ck_assert_int_eq(rgame_device_slots_instance_id(&table, 1), 999);
    ck_assert_int_eq(rgame_device_slots_count(&table), 2);

    /* Pad A can still reclaim slot 0 afterwards. */
    ck_assert_int_eq(rgame_device_slots_connect(&table, &a, 998), 0);
    ck_assert_int_eq(rgame_device_slots_count(&table), 3);
}
END_TEST

START_TEST(the_highest_slot_is_reclaimed_even_when_lower_ones_are_free) {
    /* The same discrimination as above, pushed to the last slot: a pad in
     * slot 3 that drops out and returns must not be pulled down to slot 0. */
    rgame_device_slots table;
    rgame_device_slots_init(&table);

    for (int i = 0; i < RGAME_MAX_DEVICE_SLOTS; i++) {
        rgame_device_guid g = guid_of((unsigned char)(0x10 * (i + 1)));
        ck_assert_int_eq(rgame_device_slots_connect(&table, &g, 400 + i), i);
    }
    for (int i = 0; i < RGAME_MAX_DEVICE_SLOTS; i++) {
        ck_assert_int_eq(rgame_device_slots_disconnect(&table, 400 + i), i);
    }
    ck_assert_int_eq(rgame_device_slots_count(&table), 0);

    rgame_device_guid last = guid_of((unsigned char)(0x10 * RGAME_MAX_DEVICE_SLOTS));
    ck_assert_int_eq(rgame_device_slots_connect(&table, &last, 777),
                     RGAME_MAX_DEVICE_SLOTS - 1);
}
END_TEST

START_TEST(a_different_pad_takes_a_free_slot_rather_than_stealing_a_remembered_one) {
    rgame_device_slots table;
    rgame_device_slots_init(&table);

    rgame_device_guid a = guid_of(0x10);
    rgame_device_guid b = guid_of(0x20);

    ck_assert_int_eq(rgame_device_slots_connect(&table, &a, 101), 0);
    ck_assert_int_eq(rgame_device_slots_disconnect(&table, 101), 0);

    /* Slot 0 remembers pad A. A *different* model arrives: it is free to take
     * slot 0, because nothing is using it — the remembered GUID is a
     * preference for pad A, not a reservation against everyone else. */
    ck_assert_int_eq(rgame_device_slots_connect(&table, &b, 102), 0);

    /* But now pad A returning must NOT evict pad B; it takes the next slot. */
    ck_assert_int_eq(rgame_device_slots_connect(&table, &a, 103), 1);
    ck_assert_int_eq(rgame_device_slots_instance_id(&table, 0), 102);
    ck_assert_int_eq(rgame_device_slots_instance_id(&table, 1), 103);
}
END_TEST

START_TEST(a_fifth_pad_is_rejected_without_disturbing_the_four) {
    rgame_device_slots table;
    rgame_device_slots_init(&table);

    rgame_device_guid a = guid_of(0x10);
    for (int i = 0; i < RGAME_MAX_DEVICE_SLOTS; i++) {
        ck_assert_int_eq(rgame_device_slots_connect(&table, &a, 200 + i), i);
    }
    ck_assert_int_eq(rgame_device_slots_count(&table), RGAME_MAX_DEVICE_SLOTS);

    rgame_device_guid e = guid_of(0x50);
    ck_assert_int_eq(rgame_device_slots_connect(&table, &e, 250), RGAME_DEVICE_SLOT_NONE);

    /* The four already seated players are untouched. */
    ck_assert_int_eq(rgame_device_slots_count(&table), RGAME_MAX_DEVICE_SLOTS);
    for (int i = 0; i < RGAME_MAX_DEVICE_SLOTS; i++) {
        ck_assert_int_eq(rgame_device_slots_instance_id(&table, i), 200 + i);
    }
}
END_TEST

START_TEST(two_identical_pads_get_their_own_slots_back) {
    /* The ambiguity the header warns about: identical hardware shares a GUID,
     * so slot 0 and slot 1 both remember the same bytes. Unplugging one must
     * still return it to a slot, and must not disturb the other. */
    rgame_device_slots table;
    rgame_device_slots_init(&table);

    rgame_device_guid pad = guid_of(0x77);
    ck_assert_int_eq(rgame_device_slots_connect(&table, &pad, 301), 0);
    ck_assert_int_eq(rgame_device_slots_connect(&table, &pad, 302), 1);

    /* Player 2's pad drops out and comes back. */
    ck_assert_int_eq(rgame_device_slots_disconnect(&table, 302), 1);
    ck_assert_int_eq(rgame_device_slots_connect(&table, &pad, 303), 1);

    ck_assert_int_eq(rgame_device_slots_instance_id(&table, 0), 301);
    ck_assert_int_eq(rgame_device_slots_instance_id(&table, 1), 303);
    ck_assert_int_eq(rgame_device_slots_count(&table), 2);
}
END_TEST

START_TEST(disconnecting_an_unknown_device_reports_none) {
    rgame_device_slots table;
    rgame_device_slots_init(&table);

    rgame_device_guid a = guid_of(0x10);
    rgame_device_slots_connect(&table, &a, 101);

    ck_assert_int_eq(rgame_device_slots_disconnect(&table, 555), RGAME_DEVICE_SLOT_NONE);
    ck_assert_int_eq(rgame_device_slots_count(&table), 1);

    /* Disconnecting twice is a no-op the second time, not a double-free of the slot. */
    ck_assert_int_eq(rgame_device_slots_disconnect(&table, 101), 0);
    ck_assert_int_eq(rgame_device_slots_disconnect(&table, 101), RGAME_DEVICE_SLOT_NONE);
    ck_assert_int_eq(rgame_device_slots_count(&table), 0);
}
END_TEST

START_TEST(connecting_the_same_instance_twice_keeps_one_slot) {
    rgame_device_slots table;
    rgame_device_slots_init(&table);

    rgame_device_guid a = guid_of(0x10);
    ck_assert_int_eq(rgame_device_slots_connect(&table, &a, 101), 0);
    ck_assert_int_eq(rgame_device_slots_connect(&table, &a, 101), 0);
    ck_assert_int_eq(rgame_device_slots_count(&table), 1);
}
END_TEST

START_TEST(out_of_range_slots_are_reported_empty_not_crashes) {
    rgame_device_slots table;
    rgame_device_slots_init(&table);

    ck_assert_int_eq(rgame_device_slots_connected(&table, -1), 0);
    ck_assert_int_eq(rgame_device_slots_connected(&table, RGAME_MAX_DEVICE_SLOTS), 0);
    ck_assert_int_eq(rgame_device_slots_instance_id(&table, -1), RGAME_DEVICE_SLOT_NONE);
    ck_assert_int_eq(rgame_device_slots_instance_id(&table, RGAME_MAX_DEVICE_SLOTS),
                     RGAME_DEVICE_SLOT_NONE);
}
END_TEST

Suite *device_slots_suite(void) {
    Suite *suite = suite_create("device_slots");

    TCase *tc_assign = tcase_create("assignment");
    tcase_add_test(tc_assign, init_leaves_every_slot_empty);
    tcase_add_test(tc_assign, slots_fill_lowest_first);
    tcase_add_test(tc_assign, a_fifth_pad_is_rejected_without_disturbing_the_four);
    tcase_add_test(tc_assign, connecting_the_same_instance_twice_keeps_one_slot);
    tcase_add_test(tc_assign, out_of_range_slots_are_reported_empty_not_crashes);
    suite_add_tcase(suite, tc_assign);

    TCase *tc_hotplug = tcase_create("hotplug");
    tcase_add_test(tc_hotplug, reconnecting_the_same_pad_reclaims_its_slot);
    tcase_add_test(tc_hotplug, the_highest_slot_is_reclaimed_even_when_lower_ones_are_free);
    tcase_add_test(tc_hotplug, a_different_pad_takes_a_free_slot_rather_than_stealing_a_remembered_one);
    tcase_add_test(tc_hotplug, two_identical_pads_get_their_own_slots_back);
    tcase_add_test(tc_hotplug, disconnecting_an_unknown_device_reports_none);
    suite_add_tcase(suite, tc_hotplug);

    return suite;
}
