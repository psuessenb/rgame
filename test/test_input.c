#include <check.h>

#include "input.h"
#include "suites.h"

/*
 * The snapshot is a plain struct, so every query below is exercised by filling
 * it directly — no SDL, no window, no keyboard.
 */

static void hold(rgame_input_state *state, int scancode) {
    state->keys[scancode] = 1;
}

/* --- the flat button-id space --- */

START_TEST(keyboard_and_gamepad_ranges_do_not_overlap) {
    ck_assert_int_eq(rgame_button_is_keyboard(RGAME_BUTTON_KEYBOARD_FIRST), 1);
    ck_assert_int_eq(rgame_button_is_keyboard(RGAME_BUTTON_KEYBOARD_LAST), 1);
    ck_assert_int_eq(rgame_button_is_keyboard(RGAME_BUTTON_GAMEPAD_FIRST), 0);

    ck_assert_int_eq(rgame_button_is_gamepad(RGAME_BUTTON_GAMEPAD_FIRST), 1);
    ck_assert_int_eq(rgame_button_is_gamepad(RGAME_BUTTON_GAMEPAD_LAST), 1);
    ck_assert_int_eq(rgame_button_is_gamepad(RGAME_BUTTON_KEYBOARD_LAST), 0);

    /* The ranges must abut without a gap and without overlapping, or an id
     * could belong to both device classes or to neither. */
    ck_assert_int_eq(RGAME_BUTTON_KEYBOARD_LAST + 1, RGAME_BUTTON_GAMEPAD_FIRST);
}
END_TEST

START_TEST(named_keys_all_sit_in_the_keyboard_range) {
    const int keys[] = { RGAME_KEY_RETURN, RGAME_KEY_ESCAPE, RGAME_KEY_SPACE,
                         RGAME_KEY_F1, RGAME_KEY_RIGHT, RGAME_KEY_LEFT,
                         RGAME_KEY_DOWN, RGAME_KEY_UP };
    for (size_t i = 0; i < sizeof(keys) / sizeof(keys[0]); i++) {
        ck_assert_int_eq(rgame_button_is_keyboard(keys[i]), 1);
        ck_assert_int_lt(keys[i], RGAME_KEYBOARD_KEY_COUNT);
    }
}
END_TEST

START_TEST(device_ids_are_the_keyboard_then_one_per_gamepad_slot) {
    ck_assert_int_eq(rgame_input_device_valid(RGAME_INPUT_KEYBOARD), 1);
    for (int slot = 0; slot < RGAME_INPUT_MAX_GAMEPADS; slot++) {
        ck_assert_int_eq(rgame_input_device_valid(RGAME_INPUT_GAMEPAD(slot)), 1);
    }
    ck_assert_int_eq(rgame_input_device_valid(-1), 0);
    ck_assert_int_eq(rgame_input_device_valid(RGAME_INPUT_DEVICE_COUNT), 0);

    /* The keyboard must stay device 0 so single-player callers can omit it. */
    ck_assert_int_eq(RGAME_INPUT_KEYBOARD, 0);
    /* Gamepad numbering must not collide with the keyboard. */
    ck_assert_int_gt(RGAME_INPUT_GAMEPAD(0), RGAME_INPUT_KEYBOARD);
}
END_TEST

/* --- querying the snapshot --- */

START_TEST(cleared_state_reports_nothing_held) {
    rgame_input_state state;
    rgame_input_state_clear(&state);

    ck_assert_int_eq(rgame_input_state_down(&state, RGAME_INPUT_KEYBOARD, RGAME_KEY_LEFT), 0);
    ck_assert_int_eq(rgame_input_state_down(&state, RGAME_INPUT_KEYBOARD, RGAME_KEY_SPACE), 0);
}
END_TEST

START_TEST(a_held_key_reads_back_and_others_do_not) {
    rgame_input_state state;
    rgame_input_state_clear(&state);
    hold(&state, RGAME_KEY_LEFT);

    ck_assert_int_eq(rgame_input_state_down(&state, RGAME_INPUT_KEYBOARD, RGAME_KEY_LEFT), 1);
    ck_assert_int_eq(rgame_input_state_down(&state, RGAME_INPUT_KEYBOARD, RGAME_KEY_RIGHT), 0);
}
END_TEST

START_TEST(several_keys_can_be_held_at_once) {
    rgame_input_state state;
    rgame_input_state_clear(&state);
    hold(&state, RGAME_KEY_UP);
    hold(&state, RGAME_KEY_SPACE);

    ck_assert_int_eq(rgame_input_state_down(&state, RGAME_INPUT_KEYBOARD, RGAME_KEY_UP), 1);
    ck_assert_int_eq(rgame_input_state_down(&state, RGAME_INPUT_KEYBOARD, RGAME_KEY_SPACE), 1);
    ck_assert_int_eq(rgame_input_state_down(&state, RGAME_INPUT_KEYBOARD, RGAME_KEY_DOWN), 0);
}
END_TEST

START_TEST(set_keys_replaces_the_whole_snapshot) {
    rgame_input_state state;
    rgame_input_state_clear(&state);
    hold(&state, RGAME_KEY_LEFT);

    /* A later frame in which only Right is held must clear Left, not accumulate. */
    unsigned char frame[RGAME_KEYBOARD_KEY_COUNT] = { 0 };
    frame[RGAME_KEY_RIGHT] = 1;
    rgame_input_state_set_keys(&state, frame);

    ck_assert_int_eq(rgame_input_state_down(&state, RGAME_INPUT_KEYBOARD, RGAME_KEY_LEFT), 0);
    ck_assert_int_eq(rgame_input_state_down(&state, RGAME_INPUT_KEYBOARD, RGAME_KEY_RIGHT), 1);
}
END_TEST

START_TEST(any_nonzero_byte_counts_as_held) {
    /* SDL documents its state array as "non-zero if pressed", not "== 1". */
    rgame_input_state state;
    rgame_input_state_clear(&state);
    state.keys[RGAME_KEY_UP] = 255;

    ck_assert_int_eq(rgame_input_state_down(&state, RGAME_INPUT_KEYBOARD, RGAME_KEY_UP), 1);
}
END_TEST

/* --- the cross-device and out-of-range rules --- */

START_TEST(a_device_only_answers_for_its_own_button_range) {
    rgame_input_state state;
    rgame_input_state_clear(&state);
    hold(&state, RGAME_KEY_LEFT);

    /* Asking a gamepad about a keyboard key is "not held", never the
     * keyboard's answer — otherwise player 2's pad would echo player 1. */
    ck_assert_int_eq(rgame_input_state_down(&state, RGAME_INPUT_GAMEPAD(0), RGAME_KEY_LEFT), 0);
    /* And the keyboard does not answer for gamepad buttons. */
    ck_assert_int_eq(
        rgame_input_state_down(&state, RGAME_INPUT_KEYBOARD, RGAME_BUTTON_GAMEPAD_FIRST), 0);
}
END_TEST

START_TEST(unknown_devices_and_buttons_are_not_held_rather_than_crashes) {
    rgame_input_state state;
    rgame_input_state_clear(&state);
    hold(&state, RGAME_KEY_LEFT);

    ck_assert_int_eq(rgame_input_state_down(&state, -1, RGAME_KEY_LEFT), 0);
    ck_assert_int_eq(rgame_input_state_down(&state, RGAME_INPUT_DEVICE_COUNT, RGAME_KEY_LEFT), 0);
    ck_assert_int_eq(rgame_input_state_down(&state, RGAME_INPUT_KEYBOARD, -1), 0);
    ck_assert_int_eq(rgame_input_state_down(&state, RGAME_INPUT_KEYBOARD, 0x7FFF), 0);
}
END_TEST

START_TEST(keyboard_range_beyond_the_scancode_array_is_not_read) {
    /* The keyboard *range* (up to 0x0FFF) is wider than the scancodes SDL
     * defines (512). Ids in the gap are in-range but have no array slot, and
     * must be reported unheld rather than read out of bounds — a read the
     * sanitizer build would catch, but only if something asks for it. */
    rgame_input_state state;
    rgame_input_state_clear(&state);

    ck_assert_int_eq(rgame_button_is_keyboard(RGAME_KEYBOARD_KEY_COUNT), 1);
    ck_assert_int_eq(
        rgame_input_state_down(&state, RGAME_INPUT_KEYBOARD, RGAME_KEYBOARD_KEY_COUNT), 0);
    ck_assert_int_eq(
        rgame_input_state_down(&state, RGAME_INPUT_KEYBOARD, RGAME_BUTTON_KEYBOARD_LAST), 0);
}
END_TEST

START_TEST(gamepad_devices_report_nothing_until_the_pad_shim_exists) {
    rgame_input_state state;
    rgame_input_state_clear(&state);

    for (int slot = 0; slot < RGAME_INPUT_MAX_GAMEPADS; slot++) {
        ck_assert_int_eq(
            rgame_input_state_down(&state, RGAME_INPUT_GAMEPAD(slot),
                                   RGAME_BUTTON_GAMEPAD_FIRST), 0);
    }
}
END_TEST

Suite *input_suite(void) {
    Suite *suite = suite_create("input");

    TCase *tc_space = tcase_create("button_id_space");
    tcase_add_test(tc_space, keyboard_and_gamepad_ranges_do_not_overlap);
    tcase_add_test(tc_space, named_keys_all_sit_in_the_keyboard_range);
    tcase_add_test(tc_space, device_ids_are_the_keyboard_then_one_per_gamepad_slot);
    suite_add_tcase(suite, tc_space);

    TCase *tc_snapshot = tcase_create("snapshot");
    tcase_add_test(tc_snapshot, cleared_state_reports_nothing_held);
    tcase_add_test(tc_snapshot, a_held_key_reads_back_and_others_do_not);
    tcase_add_test(tc_snapshot, several_keys_can_be_held_at_once);
    tcase_add_test(tc_snapshot, set_keys_replaces_the_whole_snapshot);
    tcase_add_test(tc_snapshot, any_nonzero_byte_counts_as_held);
    suite_add_tcase(suite, tc_snapshot);

    TCase *tc_bounds = tcase_create("bounds");
    tcase_add_test(tc_bounds, a_device_only_answers_for_its_own_button_range);
    tcase_add_test(tc_bounds, unknown_devices_and_buttons_are_not_held_rather_than_crashes);
    tcase_add_test(tc_bounds, keyboard_range_beyond_the_scancode_array_is_not_read);
    tcase_add_test(tc_bounds, gamepad_devices_report_nothing_until_the_pad_shim_exists);
    suite_add_tcase(suite, tc_bounds);

    return suite;
}
