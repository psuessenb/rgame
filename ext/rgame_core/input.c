#include "input.h"

#include <string.h>

int rgame_button_is_keyboard(int button_id) {
    return button_id >= RGAME_BUTTON_KEYBOARD_FIRST &&
           button_id <= RGAME_BUTTON_KEYBOARD_LAST;
}

int rgame_button_is_gamepad(int button_id) {
    return button_id >= RGAME_BUTTON_GAMEPAD_FIRST &&
           button_id <= RGAME_BUTTON_GAMEPAD_LAST;
}

int rgame_input_device_valid(int device) {
    return device >= 0 && device < RGAME_INPUT_DEVICE_COUNT;
}

void rgame_input_state_clear(rgame_input_state *state) {
    memset(state->keys, 0, sizeof(state->keys));
}

void rgame_input_state_set_keys(rgame_input_state *state, const unsigned char *keys) {
    memcpy(state->keys, keys, sizeof(state->keys));
}

int rgame_input_state_down(const rgame_input_state *state, int device, int button_id) {
    /* Looks redundant today — every non-keyboard device falls through to the
     * "nothing held" return below anyway — but it is what will keep the
     * per-slot gamepad arrays in bounds once the pad shim indexes by slot.
     * Deleting it now would be invisible; deleting it then would be a buffer
     * overrun. */
    if (!rgame_input_device_valid(device)) {
        return 0;
    }

    if (device == RGAME_INPUT_KEYBOARD) {
        /* A gamepad button asked of the keyboard is simply not held. */
        if (!rgame_button_is_keyboard(button_id)) {
            return 0;
        }
        /* The keyboard range (0x0FFF) is wider than the scancodes SDL actually
         * defines, so the array bound is checked separately from the range. */
        if (button_id >= RGAME_KEYBOARD_KEY_COUNT) {
            return 0;
        }
        return state->keys[button_id] ? 1 : 0;
    }

    /* Gamepad devices: the slot table and per-pad button state land with the
     * gamepad shim. Until then a pad reports nothing held, which is also the
     * correct answer for a slot with no controller plugged into it. */
    return 0;
}
