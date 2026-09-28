/*
 * teardown_queue.c — the list behind teardown_queue.h. Pure: no SDL, no locks;
 * app.c serialises every call.
 */

#include "app/teardown_queue.h"

#include <stdlib.h>

int rgame_teardown_queue_push(rgame_teardown_queue *queue, rgame_teardown_fn teardown,
                              void *object, uint64_t owner_thread) {
    if (queue->count == queue->capacity) {
        int capacity = queue->capacity > 0 ? queue->capacity * 2 : 8;
        rgame_teardown *grown = realloc(queue->entries, (size_t)capacity * sizeof(rgame_teardown));
        if (!grown) {
            return 0;
        }
        queue->entries = grown;
        queue->capacity = capacity;
    }

    queue->entries[queue->count++] = (rgame_teardown){ teardown, object, owner_thread };
    return 1;
}

int rgame_teardown_queue_take(rgame_teardown_queue *queue, uint64_t thread,
                              rgame_teardown_queue *out) {
    int matching = 0;
    for (int i = 0; i < queue->count; i++) {
        matching += queue->entries[i].owner_thread == thread;
    }
    if (matching == 0) {
        return 0;
    }

    rgame_teardown *taken = malloc((size_t)matching * sizeof(rgame_teardown));
    if (!taken) {
        return 0;
    }

    int kept = 0;
    int moved = 0;
    for (int i = 0; i < queue->count; i++) {
        if (queue->entries[i].owner_thread == thread) {
            taken[moved++] = queue->entries[i];
        } else {
            queue->entries[kept++] = queue->entries[i];
        }
    }
    queue->count = kept;

    out->entries = taken;
    out->count = moved;
    out->capacity = moved;
    return moved;
}

void rgame_teardown_queue_run(rgame_teardown_queue *queue) {
    for (int i = 0; i < queue->count; i++) {
        queue->entries[i].teardown(queue->entries[i].object);
    }
    rgame_teardown_queue_free(queue);
}

void rgame_teardown_queue_free(rgame_teardown_queue *queue) {
    free(queue->entries);
    queue->entries = NULL;
    queue->count = 0;
    queue->capacity = 0;
}
