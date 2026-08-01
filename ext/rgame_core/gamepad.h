#ifndef RGAME_GAMEPAD_H
#define RGAME_GAMEPAD_H

#include "device_slots.h"
#include "input.h"

/*
 * The game-controller shim — "layer 3", the thin real SDL part.
 *
 * Deliberately dumb. Every decision about *which player a pad belongs to*
 * lives in device_slots.{c,h}, and every decision about *what a button id
 * means* lives in input.{c,h}; both are pure and unit-tested. What is left
 * here is opening and closing SDL handles and copying values, which is little
 * enough to get wrong that it justifies not unit-testing it directly (see
 * CLAUDE.md's verification tiers).
 *
 * The SDL_GameController pointers are held as void* so this header stays free
 * of SDL types and can be included from app.c without ordering constraints —
 * the same reason include/rgame/core.h names none either.
 */

typedef struct {
    rgame_device_slots slots;
    /* SDL_GameController* per player slot; NULL when the slot is empty. */
    void *controllers[RGAME_INPUT_MAX_GAMEPADS];
} rgame_gamepads;

void rgame_gamepads_init(rgame_gamepads *pads);

/* Closes every open controller. Safe to call twice. */
void rgame_gamepads_shutdown(rgame_gamepads *pads);

/*
 * Opens the controller at SDL device index `device_index` and seats it in a
 * player slot. Returns the slot, or RGAME_DEVICE_SLOT_NONE if the device isn't
 * a game controller, can't be opened, or every slot is taken.
 *
 * Note `device_index` is SDL's *device index*, which is what
 * SDL_CONTROLLERDEVICEADDED reports — not the instance id.
 */
int rgame_gamepads_add(rgame_gamepads *pads, int device_index);

/*
 * Releases the controller with SDL instance id `instance_id` and frees its
 * slot, returning that slot or RGAME_DEVICE_SLOT_NONE if it wasn't seated.
 *
 * Note SDL_CONTROLLERDEVICEREMOVED reports an *instance id*, not a device
 * index — the two are different numbers in the same `which` field, which is
 * an easy and silent mistake to make.
 */
int rgame_gamepads_remove(rgame_gamepads *pads, int instance_id);

/* Copies every connected pad's buttons and axes into the frame snapshot, and
 * zeroes the slots that have no controller. */
void rgame_gamepads_snapshot(const rgame_gamepads *pads, rgame_input_state *state);

int rgame_gamepads_connected(const rgame_gamepads *pads, int slot);
int rgame_gamepads_count(const rgame_gamepads *pads);

/* Display name of the pad in `slot`, or NULL when empty. Owned by SDL. */
const char *rgame_gamepads_name(const rgame_gamepads *pads, int slot);

#endif /* RGAME_GAMEPAD_H */
