#include "input/gamepad.h"

#include <SDL2/SDL.h>

/* The pure modules size their arrays from these; if SDL ever grows a button or
 * an axis, the snapshot copies below would silently truncate without this. */
_Static_assert(RGAME_GAMEPAD_BUTTON_COUNT == SDL_CONTROLLER_BUTTON_MAX,
               "RGAME_GAMEPAD_BUTTON_COUNT must match SDL_CONTROLLER_BUTTON_MAX");
_Static_assert(RGAME_GAMEPAD_AXIS_COUNT == SDL_CONTROLLER_AXIS_MAX,
               "RGAME_GAMEPAD_AXIS_COUNT must match SDL_CONTROLLER_AXIS_MAX");

/* Gamepad button ids are the gamepad range plus SDL's own button number, so
 * each named id must line up with the SDL constant it mirrors. */
_Static_assert(RGAME_PAD_A ==
                   RGAME_BUTTON_GAMEPAD_FIRST + SDL_CONTROLLER_BUTTON_A,
               "pad id must match SDL controller button");
_Static_assert(RGAME_PAD_B ==
                   RGAME_BUTTON_GAMEPAD_FIRST + SDL_CONTROLLER_BUTTON_B,
               "pad id must match SDL controller button");
_Static_assert(RGAME_PAD_X ==
                   RGAME_BUTTON_GAMEPAD_FIRST + SDL_CONTROLLER_BUTTON_X,
               "pad id must match SDL controller button");
_Static_assert(RGAME_PAD_Y ==
                   RGAME_BUTTON_GAMEPAD_FIRST + SDL_CONTROLLER_BUTTON_Y,
               "pad id must match SDL controller button");
_Static_assert(RGAME_PAD_BACK ==
                   RGAME_BUTTON_GAMEPAD_FIRST + SDL_CONTROLLER_BUTTON_BACK,
               "pad id must match SDL controller button");
_Static_assert(RGAME_PAD_GUIDE ==
                   RGAME_BUTTON_GAMEPAD_FIRST + SDL_CONTROLLER_BUTTON_GUIDE,
               "pad id must match SDL controller button");
_Static_assert(RGAME_PAD_START ==
                   RGAME_BUTTON_GAMEPAD_FIRST + SDL_CONTROLLER_BUTTON_START,
               "pad id must match SDL controller button");
_Static_assert(RGAME_PAD_LEFT_STICK ==
                   RGAME_BUTTON_GAMEPAD_FIRST + SDL_CONTROLLER_BUTTON_LEFTSTICK,
               "pad id must match SDL controller button");
_Static_assert(RGAME_PAD_RIGHT_STICK ==
                   RGAME_BUTTON_GAMEPAD_FIRST + SDL_CONTROLLER_BUTTON_RIGHTSTICK,
               "pad id must match SDL controller button");
_Static_assert(RGAME_PAD_LEFT_SHOULDER ==
                   RGAME_BUTTON_GAMEPAD_FIRST + SDL_CONTROLLER_BUTTON_LEFTSHOULDER,
               "pad id must match SDL controller button");
_Static_assert(RGAME_PAD_RIGHT_SHOULDER ==
                   RGAME_BUTTON_GAMEPAD_FIRST + SDL_CONTROLLER_BUTTON_RIGHTSHOULDER,
               "pad id must match SDL controller button");
_Static_assert(RGAME_PAD_DPAD_UP ==
                   RGAME_BUTTON_GAMEPAD_FIRST + SDL_CONTROLLER_BUTTON_DPAD_UP,
               "pad id must match SDL controller button");
_Static_assert(RGAME_PAD_DPAD_DOWN ==
                   RGAME_BUTTON_GAMEPAD_FIRST + SDL_CONTROLLER_BUTTON_DPAD_DOWN,
               "pad id must match SDL controller button");
_Static_assert(RGAME_PAD_DPAD_LEFT ==
                   RGAME_BUTTON_GAMEPAD_FIRST + SDL_CONTROLLER_BUTTON_DPAD_LEFT,
               "pad id must match SDL controller button");
_Static_assert(RGAME_PAD_DPAD_RIGHT ==
                   RGAME_BUTTON_GAMEPAD_FIRST + SDL_CONTROLLER_BUTTON_DPAD_RIGHT,
               "pad id must match SDL controller button");
_Static_assert(RGAME_PAD_MISC1 ==
                   RGAME_BUTTON_GAMEPAD_FIRST + SDL_CONTROLLER_BUTTON_MISC1,
               "pad id must match SDL controller button");
_Static_assert(RGAME_PAD_PADDLE1 ==
                   RGAME_BUTTON_GAMEPAD_FIRST + SDL_CONTROLLER_BUTTON_PADDLE1,
               "pad id must match SDL controller button");
_Static_assert(RGAME_PAD_PADDLE2 ==
                   RGAME_BUTTON_GAMEPAD_FIRST + SDL_CONTROLLER_BUTTON_PADDLE2,
               "pad id must match SDL controller button");
_Static_assert(RGAME_PAD_PADDLE3 ==
                   RGAME_BUTTON_GAMEPAD_FIRST + SDL_CONTROLLER_BUTTON_PADDLE3,
               "pad id must match SDL controller button");
_Static_assert(RGAME_PAD_PADDLE4 ==
                   RGAME_BUTTON_GAMEPAD_FIRST + SDL_CONTROLLER_BUTTON_PADDLE4,
               "pad id must match SDL controller button");
_Static_assert(RGAME_PAD_TOUCHPAD ==
                   RGAME_BUTTON_GAMEPAD_FIRST + SDL_CONTROLLER_BUTTON_TOUCHPAD,
               "pad id must match SDL controller button");
_Static_assert(RGAME_AXIS_LEFT_X == SDL_CONTROLLER_AXIS_LEFTX, "axis id must match SDL axis");
_Static_assert(RGAME_AXIS_TRIGGER_RIGHT == SDL_CONTROLLER_AXIS_TRIGGERRIGHT,
               "axis id must match SDL axis");

/* Every named pad id must land inside the gamepad range, or a query would be
 * rejected as belonging to a different device class. */
_Static_assert(RGAME_BUTTON_GAMEPAD_FIRST + SDL_CONTROLLER_BUTTON_MAX - 1 <=
                   RGAME_BUTTON_GAMEPAD_LAST,
               "SDL controller buttons must fit the gamepad button-id range");

static SDL_GameController *controller_at(const rgame_gamepads *pads, int slot) {
    if (slot < 0 || slot >= RGAME_INPUT_MAX_GAMEPADS) {
        return NULL;
    }
    return (SDL_GameController *)pads->controllers[slot];
}

void rgame_gamepads_init(rgame_gamepads *pads) {
    rgame_device_slots_init(&pads->slots);
    for (int i = 0; i < RGAME_INPUT_MAX_GAMEPADS; i++) {
        pads->controllers[i] = NULL;
    }
}

void rgame_gamepads_shutdown(rgame_gamepads *pads) {
    for (int i = 0; i < RGAME_INPUT_MAX_GAMEPADS; i++) {
        SDL_GameController *pad = controller_at(pads, i);
        if (pad) {
            SDL_GameControllerClose(pad);
            pads->controllers[i] = NULL;
        }
    }
    rgame_device_slots_init(&pads->slots);
}

int rgame_gamepads_add(rgame_gamepads *pads, int device_index) {
    /* A joystick is only a *game controller* if SDL has a button mapping for
     * it. Anything else (a flight stick, a dance mat) is ignored rather than
     * seated in a player slot with meaningless buttons. */
    if (!SDL_IsGameController(device_index)) {
        return RGAME_DEVICE_SLOT_NONE;
    }

    SDL_GameController *pad = SDL_GameControllerOpen(device_index);
    if (!pad) {
        SDL_Log("SDL_GameControllerOpen(%d) failed: %s", device_index, SDL_GetError());
        return RGAME_DEVICE_SLOT_NONE;
    }

    SDL_Joystick *joystick = SDL_GameControllerGetJoystick(pad);
    SDL_JoystickID instance_id = SDL_JoystickInstanceID(joystick);
    SDL_JoystickGUID sdl_guid = SDL_JoystickGetGUID(joystick);

    /* SDL_JoystickGUID is a 16-byte blob; the slot table keeps its own copy in
     * an SDL-free struct of the same size (asserted here rather than hoped). */
    _Static_assert(sizeof(sdl_guid.data) == RGAME_DEVICE_GUID_BYTES,
                   "SDL joystick GUID must be RGAME_DEVICE_GUID_BYTES long");
    rgame_device_guid guid;
    SDL_memcpy(guid.bytes, sdl_guid.data, RGAME_DEVICE_GUID_BYTES);

    int slot = rgame_device_slots_connect(&pads->slots, &guid, (int)instance_id);
    if (slot == RGAME_DEVICE_SLOT_NONE) {
        /* All four players already have a pad: don't hold a handle we can't
         * reach, or it would leak until shutdown. */
        SDL_GameControllerClose(pad);
        return RGAME_DEVICE_SLOT_NONE;
    }

    pads->controllers[slot] = pad;
    return slot;
}

int rgame_gamepads_remove(rgame_gamepads *pads, int instance_id) {
    int slot = rgame_device_slots_disconnect(&pads->slots, instance_id);
    if (slot == RGAME_DEVICE_SLOT_NONE) {
        return RGAME_DEVICE_SLOT_NONE;
    }

    SDL_GameController *pad = controller_at(pads, slot);
    if (pad) {
        SDL_GameControllerClose(pad);
        pads->controllers[slot] = NULL;
    }
    return slot;
}

void rgame_gamepads_snapshot(const rgame_gamepads *pads, rgame_input_state *state) {
    for (int slot = 0; slot < RGAME_INPUT_MAX_GAMEPADS; slot++) {
        SDL_GameController *pad = controller_at(pads, slot);
        if (!pad) {
            /* No pad: clear rather than leave the last reading, so a button
             * held at the moment of unplugging doesn't stay stuck down. */
            rgame_input_state_clear_pad(state, slot);
            continue;
        }

        unsigned char buttons[RGAME_GAMEPAD_BUTTON_COUNT];
        for (int i = 0; i < RGAME_GAMEPAD_BUTTON_COUNT; i++) {
            buttons[i] = SDL_GameControllerGetButton(pad, (SDL_GameControllerButton)i);
        }

        float axes[RGAME_GAMEPAD_AXIS_COUNT];
        for (int i = 0; i < RGAME_GAMEPAD_AXIS_COUNT; i++) {
            int raw = SDL_GameControllerGetAxis(pad, (SDL_GameControllerAxis)i);
            axes[i] = rgame_input_axis_normalize(raw);
        }

        rgame_input_state_set_pad(state, slot, buttons, axes);
    }
}

int rgame_gamepads_connected(const rgame_gamepads *pads, int slot) {
    return controller_at(pads, slot) != NULL;
}

int rgame_gamepads_count(const rgame_gamepads *pads) {
    return rgame_device_slots_count(&pads->slots);
}

const char *rgame_gamepads_name(const rgame_gamepads *pads, int slot) {
    SDL_GameController *pad = controller_at(pads, slot);
    return pad ? SDL_GameControllerName(pad) : NULL;
}
