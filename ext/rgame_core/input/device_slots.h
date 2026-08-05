#ifndef RGAME_DEVICE_SLOTS_H
#define RGAME_DEVICE_SLOTS_H

/*
 * Player slots for game controllers — pure logic, no SDL, no I/O.
 *
 * This is "layer 1" per CLAUDE.md's abstraction strategy: all the decisions
 * about *which player a controller belongs to* live here as plain arithmetic
 * over plain structs, so they can be exercised by the Check suite without ever
 * plugging in real hardware.
 *
 * The problem it solves: the engine wants a stable "player 1 / player 2 / ..."
 * index, and SDL does not provide one. SDL's joystick *device index* renumbers
 * whenever anything is plugged or unplugged, and its *instance id* is unique
 * per connection — unplug a pad and plug the same one back in and you get a
 * fresh instance id. Either would shuffle players around mid-game, which is
 * exactly what docs/c_engine_feature_specs.md rules out when it asks for
 * indices "stable across a momentary disconnect/reconnect".
 *
 * So this table owns the mapping instead. Each slot remembers the GUID of the
 * last device that filled it, even after that device disconnects. A pad that
 * comes back reclaims the slot it had; a genuinely new pad takes the lowest
 * free one.
 *
 * IMPORTANT — a GUID identifies a device *model*, not an individual unit. Two
 * identical controllers report the same GUID, so "the slot remembering this
 * GUID" can be ambiguous. The rule below resolves it by only ever reclaiming a
 * slot that is currently free, which gives the behaviour a player expects:
 * two matching pads take slots 0 and 1, and whichever one is unplugged gets
 * its own slot back when it returns.
 */

/* Four players, matching the feature spec's "up to 4 simultaneous controllers". */
#define RGAME_MAX_DEVICE_SLOTS 4

/* Matches the size of an SDL_JoystickGUID, without naming SDL here. */
#define RGAME_DEVICE_GUID_BYTES 16

/* Returned by the lookup functions when there is no such slot/device. */
#define RGAME_DEVICE_SLOT_NONE (-1)

typedef struct {
    unsigned char bytes[RGAME_DEVICE_GUID_BYTES];
} rgame_device_guid;

typedef struct {
    int connected;   /* is a device plugged into this slot right now */
    int remembered;  /* has this slot ever been filled (i.e. is `guid` meaningful) */
    int instance_id; /* caller's handle for the live device; NONE while empty */
    rgame_device_guid guid;
} rgame_device_slot;

typedef struct {
    rgame_device_slot slots[RGAME_MAX_DEVICE_SLOTS];
} rgame_device_slots;

/* Empties every slot and forgets every remembered GUID. */
void rgame_device_slots_init(rgame_device_slots *table);

/*
 * Assigns a newly connected device to a slot and returns that slot's index,
 * or RGAME_DEVICE_SLOT_NONE if all slots are already occupied.
 *
 * Order of preference:
 *   1. the device is already connected (same instance_id) — returns its slot
 *      unchanged, so a duplicate connect event is harmless;
 *   2. the lowest *free* slot that remembers this GUID — the reconnect case;
 *   3. the lowest free slot.
 */
int rgame_device_slots_connect(rgame_device_slots *table,
                               const rgame_device_guid *guid,
                               int instance_id);

/*
 * Marks the slot holding `instance_id` as free and returns its index, or
 * RGAME_DEVICE_SLOT_NONE if no slot held it. The slot keeps its remembered
 * GUID — that is the whole point, and what lets a reconnect reclaim it.
 */
int rgame_device_slots_disconnect(rgame_device_slots *table, int instance_id);

/* The slot currently holding `instance_id`, or RGAME_DEVICE_SLOT_NONE. */
int rgame_device_slots_find(const rgame_device_slots *table, int instance_id);

/* Whether a device is plugged into `slot`. Out-of-range slots are simply 0. */
int rgame_device_slots_connected(const rgame_device_slots *table, int slot);

/* The live device in `slot`, or RGAME_DEVICE_SLOT_NONE if it is empty. */
int rgame_device_slots_instance_id(const rgame_device_slots *table, int slot);

/* How many slots currently have a device plugged in. */
int rgame_device_slots_count(const rgame_device_slots *table);

#endif /* RGAME_DEVICE_SLOTS_H */
