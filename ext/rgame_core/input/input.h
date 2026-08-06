#ifndef RGAME_INPUT_H
#define RGAME_INPUT_H

#include "rgame/core.h"

/*
 * The input snapshot — pure logic, no SDL, no I/O.
 *
 * "Layer 1" per CLAUDE.md: this holds the *state* and all the rules for
 * reading it, as plain arrays and integer comparisons, so the Check suite can
 * fill a snapshot by hand and assert on every query without a keyboard, a
 * window, or an event loop existing at all.
 *
 * Only filling the snapshot from real hardware needs SDL, and that is a
 * separate handful of lines in app.c — the thin "layer 3" shim.
 *
 * Why a snapshot rather than reading hardware on demand: the engine runs a
 * fixed timestep, so one rendered frame may run zero or several simulation
 * ticks. If a tick asked the hardware directly, the same held key could read
 * differently between two ticks of the same frame, and how many ticks ran
 * depends on how long the last frame took. Sampling once per frame makes the
 * answer constant across the whole frame.
 *
 * Note what this does *not* fix: an edge — "pressed this tick" — is a
 * comparison against the previous poll, so whatever polls decides what a press
 * is. Polling per rendered frame while simulating per tick loses presses on a
 * fast machine. See RGame::Game, which polls in `update`.
 *
 * The button-id space and device numbering both live in rgame/core.h, because
 * callers outside this directory need to name them.
 */

/* All three == the matching SDL maxima; asserted against SDL in app.c. */
#define RGAME_KEYBOARD_KEY_COUNT 512
#define RGAME_GAMEPAD_BUTTON_COUNT 21
#define RGAME_GAMEPAD_AXIS_COUNT 6

typedef struct {
    /* One byte per scancode: non-zero means held. A byte array rather than a
     * bitset because it is what SDL_GetKeyboardState already hands us, so the
     * snapshot is a straight copy with no packing step on the frame path. */
    unsigned char keys[RGAME_KEYBOARD_KEY_COUNT];

    /* Per player slot, not per SDL device index — the slot table owns that
     * mapping, so a pad that is unplugged and replugged keeps writing here. */
    unsigned char pad_buttons[RGAME_INPUT_MAX_GAMEPADS][RGAME_GAMEPAD_BUTTON_COUNT];
    float pad_axes[RGAME_INPUT_MAX_GAMEPADS][RGAME_GAMEPAD_AXIS_COUNT];
} rgame_input_state;

/* Clears every button to "not held". */
void rgame_input_state_clear(rgame_input_state *state);

/* Replaces the keyboard half of the snapshot. `keys` must have
 * RGAME_KEYBOARD_KEY_COUNT entries, non-zero meaning held — the exact shape
 * SDL_GetKeyboardState returns. */
void rgame_input_state_set_keys(rgame_input_state *state, const unsigned char *keys);

/* Replaces one slot's gamepad state. `buttons` and `axes` must have
 * RGAME_GAMEPAD_BUTTON_COUNT / RGAME_GAMEPAD_AXIS_COUNT entries. */
void rgame_input_state_set_pad(rgame_input_state *state, int slot,
                               const unsigned char *buttons, const float *axes);

/* Zeroes one slot — what a disconnect must do, so a pad unplugged mid-press
 * does not leave that button stuck held forever. */
void rgame_input_state_clear_pad(rgame_input_state *state, int slot);

/*
 * Whether `button_id` is held on `device`. Returns 0 rather than raising for
 * every out-of-range case: an unknown device, a button outside any range, or a
 * button belonging to a different device class than the one asked about.
 */
int rgame_input_state_down(const rgame_input_state *state, int device, int button_id);

/* Current value of `axis_id` on `device`; 0.0 for anything out of range. */
float rgame_input_state_axis(const rgame_input_state *state, int device, int axis_id);

/*
 * Converts a raw SDL axis reading (-32768..32767) to -1.0..1.0.
 *
 * The range is asymmetric — there is one more negative value than positive —
 * so dividing by 32767 would make full-left read slightly past -1.0. The
 * result is clamped instead, which costs nothing and keeps callers from having
 * to special-case a single value.
 */
float rgame_input_axis_normalize(int raw);

/* The player slot a gamepad device id refers to, or -1 for the keyboard or an
 * invalid device. */
int rgame_input_device_slot(int device);

/* Range predicates for the flat button-id space. Exposed because they are the
 * part worth testing directly, and because app.c uses them too. */
int rgame_button_is_keyboard(int button_id);
int rgame_button_is_gamepad(int button_id);

/* Whether `device` names the keyboard or a real gamepad slot. */
int rgame_input_device_valid(int device);

#endif /* RGAME_INPUT_H */
