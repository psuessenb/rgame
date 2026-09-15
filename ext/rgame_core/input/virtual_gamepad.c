/*
 * virtual_gamepad.c — a synthetic SDL game controller, for tests.
 *
 * Layer 3, and thin: every function is one or two SDL calls. What earns it a
 * file in the engine rather than in a spec helper is *which* SDL it calls. A
 * helper reaching SDL from outside the extension has to find it by name or by
 * exported symbol, and neither works on every platform once SDL is linked into
 * core_ext statically: on Windows the extension exports no SDL symbol, and a
 * library name resolves to some other copy of SDL. Code compiled into the
 * engine can only call the SDL the engine runs on.
 *
 * Covered end to end by the gamepad and input specs in spec_core/, which drive
 * an app's real hot-plug and button path through it.
 */

#include "rgame/core.h"
#include "app/sdl_session.h"

#include <SDL2/SDL.h>
#include <stdlib.h>

struct rgame_virtual_gamepad {
    SDL_Joystick *joystick;
    unsigned session;
    int detached;
};

static const char *attach_error = NULL;

static int usable(const rgame_virtual_gamepad *pad) {
    return !pad->detached && pad->session == rgame_sdl_session();
}

/*
 * The pad's device index now. SDL renumbers device indices whenever any other
 * device arrives or leaves, so the index attach returned is not kept: the
 * instance id is the stable identity, and the index is looked up from it.
 */
static int device_index(const rgame_virtual_gamepad *pad) {
    SDL_JoystickID id = SDL_JoystickInstanceID(pad->joystick);
    int count = SDL_NumJoysticks();
    for (int index = 0; index < count; index++) {
        if (SDL_JoystickGetDeviceInstanceID(index) == id) {
            return index;
        }
    }
    return -1;
}

rgame_virtual_gamepad *rgame_virtual_gamepad_attach(void) {
    attach_error = NULL;

    unsigned session = rgame_sdl_session();
    if (session == 0) {
        attach_error = "no app is open, so SDL is not running";
        return NULL;
    }

    int index = SDL_JoystickAttachVirtual(SDL_JOYSTICK_TYPE_GAMECONTROLLER, SDL_CONTROLLER_AXIS_MAX,
                                          SDL_CONTROLLER_BUTTON_MAX, 0);
    if (index < 0) {
        return NULL;
    }

    SDL_Joystick *joystick = SDL_JoystickOpen(index);
    if (!joystick) {
        SDL_JoystickDetachVirtual(index);
        return NULL;
    }

    rgame_virtual_gamepad *pad = calloc(1, sizeof *pad);
    if (!pad) {
        SDL_JoystickClose(joystick);
        SDL_JoystickDetachVirtual(index);
        attach_error = "out of memory";
        return NULL;
    }
    pad->joystick = joystick;
    pad->session = session;
    return pad;
}

int rgame_virtual_gamepad_stale(const rgame_virtual_gamepad *pad) {
    return pad->session != rgame_sdl_session();
}

int rgame_virtual_gamepad_set_button(rgame_virtual_gamepad *pad, int button, int down) {
    if (!usable(pad)) {
        return -1;
    }
    int result = SDL_JoystickSetVirtualButton(pad->joystick, button, down ? SDL_PRESSED : SDL_RELEASED);
    /* Setting virtual state only queues it. An update applies it where SDL can;
     * where it cannot yet, rgame_virtual_gamepad_pump is the retry. */
    SDL_JoystickUpdate();
    return result;
}

int rgame_virtual_gamepad_set_axis(rgame_virtual_gamepad *pad, int axis, int value) {
    if (!usable(pad)) {
        return -1;
    }
    int result = SDL_JoystickSetVirtualAxis(pad->joystick, axis, (Sint16)value);
    SDL_JoystickUpdate();
    return result;
}

int rgame_virtual_gamepad_button_down(const rgame_virtual_gamepad *pad, int button) {
    return usable(pad) && SDL_JoystickGetButton(pad->joystick, button) == SDL_PRESSED;
}

int rgame_virtual_gamepad_is_game_controller(const rgame_virtual_gamepad *pad) {
    if (!usable(pad)) {
        return 0;
    }
    int index = device_index(pad);
    return index >= 0 && SDL_IsGameController(index) == SDL_TRUE;
}

int rgame_virtual_gamepad_attached(const rgame_virtual_gamepad *pad) {
    return usable(pad) && SDL_JoystickGetAttached(pad->joystick) == SDL_TRUE;
}

void rgame_virtual_gamepad_pump(void) {
    if (rgame_sdl_session() == 0) {
        return;
    }
    SDL_PumpEvents();
    SDL_JoystickUpdate();
}

void rgame_virtual_gamepad_detach(rgame_virtual_gamepad *pad) {
    if (!usable(pad)) {
        pad->detached = 1;
        return;
    }
    int index = device_index(pad);
    SDL_JoystickClose(pad->joystick);
    if (index >= 0) {
        SDL_JoystickDetachVirtual(index);
    }
    pad->joystick = NULL;
    pad->detached = 1;
}

void rgame_virtual_gamepad_free(rgame_virtual_gamepad *pad) {
    free(pad);
}

const char *rgame_virtual_gamepad_error(void) {
    return attach_error ? attach_error : SDL_GetError();
}
