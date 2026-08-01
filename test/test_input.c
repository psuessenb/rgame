#include <check.h>
#include <limits.h>

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


/* --- gamepad state --- */

static void fill_pad(rgame_input_state *state, int slot, int button, float axis_value) {
    unsigned char buttons[RGAME_GAMEPAD_BUTTON_COUNT] = { 0 };
    float axes[RGAME_GAMEPAD_AXIS_COUNT] = { 0 };
    if (button >= 0) {
        buttons[button - RGAME_BUTTON_GAMEPAD_FIRST] = 1;
    }
    axes[RGAME_AXIS_LEFT_X] = axis_value;
    rgame_input_state_set_pad(state, slot, buttons, axes);
}

START_TEST(a_pad_button_reads_back_on_its_own_slot_only) {
    rgame_input_state state;
    rgame_input_state_clear(&state);
    fill_pad(&state, 1, RGAME_PAD_A, 0.0f);

    ck_assert_int_eq(rgame_input_state_down(&state, RGAME_INPUT_GAMEPAD(1), RGAME_PAD_A), 1);
    ck_assert_int_eq(rgame_input_state_down(&state, RGAME_INPUT_GAMEPAD(1), RGAME_PAD_B), 0);
    /* Player 1's pad must not answer for player 2's — the bug that would make
     * every player move together. */
    ck_assert_int_eq(rgame_input_state_down(&state, RGAME_INPUT_GAMEPAD(0), RGAME_PAD_A), 0);
    ck_assert_int_eq(rgame_input_state_down(&state, RGAME_INPUT_KEYBOARD, RGAME_PAD_A), 0);
}
END_TEST

START_TEST(dpad_buttons_are_distinct_ids) {
    rgame_input_state state;
    rgame_input_state_clear(&state);
    fill_pad(&state, 0, RGAME_PAD_DPAD_RIGHT, 0.0f);

    ck_assert_int_eq(rgame_input_state_down(&state, RGAME_INPUT_GAMEPAD(0), RGAME_PAD_DPAD_RIGHT), 1);
    ck_assert_int_eq(rgame_input_state_down(&state, RGAME_INPUT_GAMEPAD(0), RGAME_PAD_DPAD_LEFT), 0);
    ck_assert_int_eq(rgame_input_state_down(&state, RGAME_INPUT_GAMEPAD(0), RGAME_PAD_DPAD_UP), 0);
}
END_TEST

START_TEST(clearing_a_pad_releases_buttons_held_at_disconnect) {
    rgame_input_state state;
    rgame_input_state_clear(&state);
    fill_pad(&state, 2, RGAME_PAD_A, 0.9f);
    ck_assert_int_eq(rgame_input_state_down(&state, RGAME_INPUT_GAMEPAD(2), RGAME_PAD_A), 1);

    rgame_input_state_clear_pad(&state, 2);

    /* A pad yanked out mid-press must not leave the button stuck down. */
    ck_assert_int_eq(rgame_input_state_down(&state, RGAME_INPUT_GAMEPAD(2), RGAME_PAD_A), 0);
    ck_assert_float_eq(rgame_input_state_axis(&state, RGAME_INPUT_GAMEPAD(2), RGAME_AXIS_LEFT_X), 0.0f);
}
END_TEST

START_TEST(clearing_one_pad_leaves_the_others_alone) {
    rgame_input_state state;
    rgame_input_state_clear(&state);
    fill_pad(&state, 0, RGAME_PAD_A, 0.0f);
    fill_pad(&state, 1, RGAME_PAD_A, 0.0f);

    rgame_input_state_clear_pad(&state, 0);

    ck_assert_int_eq(rgame_input_state_down(&state, RGAME_INPUT_GAMEPAD(0), RGAME_PAD_A), 0);
    ck_assert_int_eq(rgame_input_state_down(&state, RGAME_INPUT_GAMEPAD(1), RGAME_PAD_A), 1);
}
END_TEST

START_TEST(extreme_button_ids_do_not_overflow_the_index_arithmetic) {
    /* The gamepad branch computes `button_id - RGAME_BUTTON_GAMEPAD_FIRST`.
     * For a hugely negative id that subtraction is signed overflow — undefined
     * behaviour, which the range check in front of it is what prevents. Only
     * the UBSan build can see the difference, so this is here to give it
     * something to look at. */
    rgame_input_state state;
    rgame_input_state_clear(&state);

    ck_assert_int_eq(rgame_input_state_down(&state, RGAME_INPUT_GAMEPAD(0), INT_MIN), 0);
    ck_assert_int_eq(rgame_input_state_down(&state, RGAME_INPUT_GAMEPAD(0), INT_MAX), 0);
    ck_assert_int_eq(rgame_input_state_down(&state, RGAME_INPUT_KEYBOARD, INT_MIN), 0);
}
END_TEST

START_TEST(pad_ids_beyond_sdls_buttons_are_not_read) {
    /* Same gap as the keyboard has: the gamepad *range* is 256 ids wide but
     * SDL defines only RGAME_GAMEPAD_BUTTON_COUNT of them. */
    rgame_input_state state;
    rgame_input_state_clear(&state);

    int past_end = RGAME_BUTTON_GAMEPAD_FIRST + RGAME_GAMEPAD_BUTTON_COUNT;
    ck_assert_int_eq(rgame_button_is_gamepad(past_end), 1);
    ck_assert_int_eq(rgame_input_state_down(&state, RGAME_INPUT_GAMEPAD(0), past_end), 0);
    ck_assert_int_eq(
        rgame_input_state_down(&state, RGAME_INPUT_GAMEPAD(0), RGAME_BUTTON_GAMEPAD_LAST), 0);
}
END_TEST

/* --- axes --- */

START_TEST(axis_normalize_maps_the_sdl_range_to_minus_one_to_one) {
    ck_assert_float_eq_tol(rgame_input_axis_normalize(0), 0.0f, 1e-6f);
    ck_assert_float_eq_tol(rgame_input_axis_normalize(32767), 1.0f, 1e-6f);
    ck_assert_float_eq_tol(rgame_input_axis_normalize(16383), 0.5f, 1e-3f);
    ck_assert_float_eq_tol(rgame_input_axis_normalize(-16384), -0.5f, 1e-3f);
}
END_TEST

START_TEST(axis_normalize_clamps_the_asymmetric_negative_extreme) {
    /* SDL's range has one more negative value than positive, so -32768 / 32767
     * is just past -1.0. Callers must never see a magnitude above 1. */
    float full_left = rgame_input_axis_normalize(-32768);
    ck_assert_float_eq_tol(full_left, -1.0f, 1e-6f);
    ck_assert(full_left >= -1.0f);
}
END_TEST

START_TEST(axes_read_back_per_slot) {
    rgame_input_state state;
    rgame_input_state_clear(&state);
    fill_pad(&state, 3, -1, -0.75f);

    ck_assert_float_eq_tol(
        rgame_input_state_axis(&state, RGAME_INPUT_GAMEPAD(3), RGAME_AXIS_LEFT_X), -0.75f, 1e-6f);
    ck_assert_float_eq_tol(
        rgame_input_state_axis(&state, RGAME_INPUT_GAMEPAD(3), RGAME_AXIS_LEFT_Y), 0.0f, 1e-6f);
    ck_assert_float_eq_tol(
        rgame_input_state_axis(&state, RGAME_INPUT_GAMEPAD(0), RGAME_AXIS_LEFT_X), 0.0f, 1e-6f);
}
END_TEST

START_TEST(the_keyboard_and_bad_axes_read_zero) {
    rgame_input_state state;
    rgame_input_state_clear(&state);
    fill_pad(&state, 0, -1, 1.0f);

    /* The keyboard has no axes. */
    ck_assert_float_eq_tol(
        rgame_input_state_axis(&state, RGAME_INPUT_KEYBOARD, RGAME_AXIS_LEFT_X), 0.0f, 1e-6f);
    ck_assert_float_eq_tol(
        rgame_input_state_axis(&state, RGAME_INPUT_GAMEPAD(0), -1), 0.0f, 1e-6f);
    ck_assert_float_eq_tol(
        rgame_input_state_axis(&state, RGAME_INPUT_GAMEPAD(0), RGAME_GAMEPAD_AXIS_COUNT), 0.0f, 1e-6f);
    ck_assert_float_eq_tol(
        rgame_input_state_axis(&state, RGAME_INPUT_DEVICE_COUNT, RGAME_AXIS_LEFT_X), 0.0f, 1e-6f);
}
END_TEST

START_TEST(device_slot_mapping_is_the_inverse_of_the_gamepad_macro) {
    ck_assert_int_eq(rgame_input_device_slot(RGAME_INPUT_KEYBOARD), -1);
    for (int slot = 0; slot < RGAME_INPUT_MAX_GAMEPADS; slot++) {
        ck_assert_int_eq(rgame_input_device_slot(RGAME_INPUT_GAMEPAD(slot)), slot);
    }
    ck_assert_int_eq(rgame_input_device_slot(RGAME_INPUT_DEVICE_COUNT), -1);
    ck_assert_int_eq(rgame_input_device_slot(-1), -1);
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
    tcase_add_test(tc_bounds, pad_ids_beyond_sdls_buttons_are_not_read);
    tcase_add_test(tc_bounds, extreme_button_ids_do_not_overflow_the_index_arithmetic);
    suite_add_tcase(suite, tc_bounds);

    TCase *tc_pads = tcase_create("gamepads");
    tcase_add_test(tc_pads, a_pad_button_reads_back_on_its_own_slot_only);
    tcase_add_test(tc_pads, dpad_buttons_are_distinct_ids);
    tcase_add_test(tc_pads, clearing_a_pad_releases_buttons_held_at_disconnect);
    tcase_add_test(tc_pads, clearing_one_pad_leaves_the_others_alone);
    tcase_add_test(tc_pads, device_slot_mapping_is_the_inverse_of_the_gamepad_macro);
    suite_add_tcase(suite, tc_pads);

    TCase *tc_axes = tcase_create("axes");
    tcase_add_test(tc_axes, axis_normalize_maps_the_sdl_range_to_minus_one_to_one);
    tcase_add_test(tc_axes, axis_normalize_clamps_the_asymmetric_negative_extreme);
    tcase_add_test(tc_axes, axes_read_back_per_slot);
    tcase_add_test(tc_axes, the_keyboard_and_bad_axes_read_zero);
    suite_add_tcase(suite, tc_axes);

    return suite;
}
