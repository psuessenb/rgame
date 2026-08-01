#include "device_slots.h"

#include <string.h>

/* memcmp returns 0 when the two byte ranges are identical, so this reads as
 * "same GUID" rather than as an inverted comparison at each call site. */
static int guid_equal(const rgame_device_guid *a, const rgame_device_guid *b) {
    return memcmp(a->bytes, b->bytes, RGAME_DEVICE_GUID_BYTES) == 0;
}

static int slot_in_range(int slot) {
    return slot >= 0 && slot < RGAME_MAX_DEVICE_SLOTS;
}

void rgame_device_slots_init(rgame_device_slots *table) {
    for (int i = 0; i < RGAME_MAX_DEVICE_SLOTS; i++) {
        rgame_device_slot *slot = &table->slots[i];
        slot->connected = 0;
        slot->remembered = 0;
        slot->instance_id = RGAME_DEVICE_SLOT_NONE;
        memset(slot->guid.bytes, 0, RGAME_DEVICE_GUID_BYTES);
    }
}

int rgame_device_slots_find(const rgame_device_slots *table, int instance_id) {
    for (int i = 0; i < RGAME_MAX_DEVICE_SLOTS; i++) {
        const rgame_device_slot *slot = &table->slots[i];
        if (slot->connected && slot->instance_id == instance_id) {
            return i;
        }
    }
    return RGAME_DEVICE_SLOT_NONE;
}

int rgame_device_slots_connect(rgame_device_slots *table,
                               const rgame_device_guid *guid,
                               int instance_id) {
    /* Already connected: a duplicate event must not consume a second slot. */
    int existing = rgame_device_slots_find(table, instance_id);
    if (existing != RGAME_DEVICE_SLOT_NONE) {
        return existing;
    }

    /* Preferred: a free slot that remembers this GUID — the reconnect case.
     * Only free slots are considered, which is what keeps two identical pads
     * (same GUID, see the header) from fighting over one slot. */
    for (int i = 0; i < RGAME_MAX_DEVICE_SLOTS; i++) {
        rgame_device_slot *slot = &table->slots[i];
        if (!slot->connected && slot->remembered && guid_equal(&slot->guid, guid)) {
            slot->connected = 1;
            slot->instance_id = instance_id;
            return i;
        }
    }

    /* Otherwise the lowest free slot, remembering this GUID for next time. */
    for (int i = 0; i < RGAME_MAX_DEVICE_SLOTS; i++) {
        rgame_device_slot *slot = &table->slots[i];
        if (!slot->connected) {
            slot->connected = 1;
            slot->remembered = 1;
            slot->instance_id = instance_id;
            slot->guid = *guid;
            return i;
        }
    }

    /* All four players already have a controller. */
    return RGAME_DEVICE_SLOT_NONE;
}

int rgame_device_slots_disconnect(rgame_device_slots *table, int instance_id) {
    int index = rgame_device_slots_find(table, instance_id);
    if (index == RGAME_DEVICE_SLOT_NONE) {
        return RGAME_DEVICE_SLOT_NONE;
    }

    rgame_device_slot *slot = &table->slots[index];
    slot->connected = 0;
    slot->instance_id = RGAME_DEVICE_SLOT_NONE;
    /* `remembered` and `guid` deliberately survive: they are what a later
     * reconnect matches against to reclaim this same slot. */
    return index;
}

int rgame_device_slots_connected(const rgame_device_slots *table, int slot) {
    return slot_in_range(slot) ? table->slots[slot].connected : 0;
}

int rgame_device_slots_instance_id(const rgame_device_slots *table, int slot) {
    if (!slot_in_range(slot) || !table->slots[slot].connected) {
        return RGAME_DEVICE_SLOT_NONE;
    }
    return table->slots[slot].instance_id;
}

int rgame_device_slots_count(const rgame_device_slots *table) {
    int count = 0;
    for (int i = 0; i < RGAME_MAX_DEVICE_SLOTS; i++) {
        count += table->slots[i].connected ? 1 : 0;
    }
    return count;
}
