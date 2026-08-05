#include "input/input.h"

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

int rgame_input_device_slot(int device) {
    if (device < RGAME_INPUT_GAMEPAD_FIRST || device >= RGAME_INPUT_DEVICE_COUNT) {
        return -1;
    }
    return device - RGAME_INPUT_GAMEPAD_FIRST;
}

float rgame_input_axis_normalize(int raw) {
    float value = (float)raw / 32767.0f;
    if (value < -1.0f) {
        return -1.0f; /* raw == -32768 is one step past the positive limit */
    }
    if (value > 1.0f) {
        return 1.0f;
    }
    return value;
}

void rgame_input_state_clear(rgame_input_state *state) {
    memset(state->keys, 0, sizeof(state->keys));
    memset(state->pad_buttons, 0, sizeof(state->pad_buttons));
    memset(state->pad_axes, 0, sizeof(state->pad_axes));
}

void rgame_input_state_set_pad(rgame_input_state *state, int slot,
                               const unsigned char *buttons, const float *axes) {
    if (slot < 0 || slot >= RGAME_INPUT_MAX_GAMEPADS) {
        return;
    }
    memcpy(state->pad_buttons[slot], buttons, sizeof(state->pad_buttons[slot]));
    memcpy(state->pad_axes[slot], axes, sizeof(state->pad_axes[slot]));
}

void rgame_input_state_clear_pad(rgame_input_state *state, int slot) {
    if (slot < 0 || slot >= RGAME_INPUT_MAX_GAMEPADS) {
        return;
    }
    memset(state->pad_buttons[slot], 0, sizeof(state->pad_buttons[slot]));
    memset(state->pad_axes[slot], 0, sizeof(state->pad_axes[slot]));
}

float rgame_input_state_axis(const rgame_input_state *state, int device, int axis_id) {
    int slot = rgame_input_device_slot(device);
    if (slot < 0 || axis_id < 0 || axis_id >= RGAME_GAMEPAD_AXIS_COUNT) {
        return 0.0f;
    }
    return state->pad_axes[slot][axis_id];
}

void rgame_input_state_set_keys(rgame_input_state *state, const unsigned char *keys) {
    memcpy(state->keys, keys, sizeof(state->keys));
}

int rgame_input_state_down(const rgame_input_state *state, int device, int button_id) {
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

    /*
     * A gamepad answers only for gamepad buttons — and this check has to come
     * *before* the subtraction below, not merely alongside the bound check.
     * For a hugely negative id, `button_id - RGAME_BUTTON_GAMEPAD_FIRST` is
     * signed overflow, i.e. undefined behaviour, before any bound check gets a
     * chance to reject it. (Confirmed by removing this guard: UBSan reports
     * "signed integer overflow: -2147483648 - 4096".)
     */
    if (!rgame_button_is_gamepad(button_id)) {
        return 0;
    }

    /* rgame_input_device_slot rejects the keyboard and any out-of-range device
     * by returning -1, so no separate device-validity check is needed here. */
    int slot = rgame_input_device_slot(device);
    int index = button_id - RGAME_BUTTON_GAMEPAD_FIRST;
    /* The gamepad range (256 ids) is wider than the buttons SDL defines, so
     * the array bound is checked separately from the range — same split as the
     * keyboard above. A slot with no pad simply holds zeroes. */
    if (slot < 0 || index < 0 || index >= RGAME_GAMEPAD_BUTTON_COUNT) {
        return 0;
    }
    return state->pad_buttons[slot][index] ? 1 : 0;
}
