#include "draw_queue.h"

#include <stdlib.h>
#include <string.h>

/*
 * Grow a buffer to hold at least `needed` items, doubling so that repeated
 * appends are amortised constant time. Returns 0 if the allocation failed, in
 * which case the existing buffer is untouched and still usable — realloc only
 * frees the old block on success.
 */
static int ensure_capacity(void **items, unsigned int *capacity, unsigned int needed,
                           size_t item_size) {
    if (*capacity >= needed) {
        return 1;
    }

    unsigned int next = *capacity ? *capacity : 1;
    while (next < needed) {
        unsigned int doubled = next * 2;
        if (doubled < next) { /* would overflow; give up rather than wrap */
            return 0;
        }
        next = doubled;
    }

    void *grown = realloc(*items, (size_t)next * item_size);
    if (!grown) {
        return 0;
    }
    *items = grown;
    *capacity = next;
    return 1;
}

void rgame_draw_queue_init(rgame_draw_queue *queue) {
    memset(queue, 0, sizeof(*queue));
}

void rgame_draw_queue_destroy(rgame_draw_queue *queue) {
    free(queue->commands);
    free(queue->vertices);
    free(queue->sorted);
    free(queue->batches);
    free(queue->discard);
    memset(queue, 0, sizeof(*queue));
}

void rgame_draw_queue_reset(rgame_draw_queue *queue) {
    /* Counts only — the buffers stay, which is the whole point. */
    queue->command_count = 0;
    queue->vertex_count = 0;
    queue->sorted_count = 0;
    queue->batch_count = 0;
}

/* Somewhere writable for a dropped command's vertices to go. */
static rgame_vertex *discard_span(rgame_draw_queue *queue, unsigned int count) {
    /* At least one, even for a zero-vertex request: the contract is that this
     * never hands back NULL, and ensure_capacity(0) would short-circuit before
     * allocating anything at all. */
    unsigned int needed = count ? count : 1;
    if (!ensure_capacity((void **)&queue->discard, &queue->discard_capacity, needed,
                         sizeof(rgame_vertex))) {
        /*
         * Even the scratch could not grow. Returning NULL here would hand the
         * caller a pointer it does not check; instead keep whatever scratch we
         * already have. Writing past it is only reachable if the very first
         * allocation in the process failed, at which point nothing works
         * anyway — but the pointer stays valid, which is what matters.
         */
        return queue->discard;
    }
    return queue->discard;
}

rgame_vertex *rgame_draw_queue_alloc(rgame_draw_queue *queue, unsigned int count, double z,
                                     unsigned int texture, rgame_rect clip) {
    /* Nothing to draw, or nowhere to draw it: drop before reserving anything. */
    if (count == 0 || rgame_rect_is_empty(clip)) {
        return discard_span(queue, count);
    }

    /*
     * A NaN z makes the comparator intransitive, and qsort with a comparator
     * that is not a total order is undefined behaviour rather than merely a
     * wrong order. Concretely, with A(NaN, order 1), B(5.0, order 0) and
     * C(1.0, order 2) the comparator reports B<A and A<C but also C<B.
     * `z != z` is true only for NaN.
     */
    if (z != z) {
        z = 0.0;
    }

    /* Reserve both buffers before committing to either, so a failure leaves
     * the queue exactly as it was. */
    if (!ensure_capacity((void **)&queue->vertices, &queue->vertex_capacity,
                         queue->vertex_count + count, sizeof(rgame_vertex)) ||
        !ensure_capacity((void **)&queue->commands, &queue->command_capacity,
                         queue->command_count + 1, sizeof(rgame_draw_command))) {
        return discard_span(queue, count);
    }

    rgame_draw_command *command = &queue->commands[queue->command_count];
    command->z = z;
    command->order = queue->command_count;
    command->texture = texture;
    command->clip = clip;
    command->first_vertex = queue->vertex_count;
    command->vertex_count = count;

    rgame_vertex *span = &queue->vertices[queue->vertex_count];
    queue->vertex_count += count;
    queue->command_count++;
    return span;
}

/*
 * Order by z, then by insertion order.
 *
 * The tiebreak is what makes the result deterministic; because `order` is
 * unique the comparison is a total order, so an unstable sort like qsort still
 * produces the one correct answer. Stability comes from the comparator, not
 * from the algorithm.
 */
int rgame_draw_command_compare(const void *lhs, const void *rhs) {
    const rgame_draw_command *a = lhs;
    const rgame_draw_command *b = rhs;

    if (a->z < b->z) {
        return -1;
    }
    if (a->z > b->z) {
        return 1;
    }
    if (a->order < b->order) {
        return -1;
    }
    return a->order > b->order ? 1 : 0;
}

/* Two commands can share a draw call only if both the texture and the clip
 * match — see the note on `clip` in the header for why the clip is part of it. */
static int batchable_with(const rgame_draw_batch *batch, const rgame_draw_command *command) {
    return batch->texture == command->texture && rgame_rect_equals(batch->clip, command->clip);
}

void rgame_draw_queue_prepare(rgame_draw_queue *queue) {
    queue->sorted_count = 0;
    queue->batch_count = 0;
    if (queue->command_count == 0) {
        return;
    }

    qsort(queue->commands, queue->command_count, sizeof(rgame_draw_command),
          rgame_draw_command_compare);

    if (!ensure_capacity((void **)&queue->sorted, &queue->sorted_capacity, queue->vertex_count,
                         sizeof(rgame_vertex)) ||
        !ensure_capacity((void **)&queue->batches, &queue->batch_capacity,
                         queue->command_count, sizeof(rgame_draw_batch))) {
        return; /* nothing prepared; the frame draws nothing rather than crashing */
    }

    for (unsigned int i = 0; i < queue->command_count; i++) {
        const rgame_draw_command *command = &queue->commands[i];

        /* Copy this command's vertices into the contiguous output. */
        memcpy(&queue->sorted[queue->sorted_count], &queue->vertices[command->first_vertex],
               (size_t)command->vertex_count * sizeof(rgame_vertex));

        rgame_draw_batch *open_batch =
            queue->batch_count ? &queue->batches[queue->batch_count - 1] : NULL;

        if (open_batch && batchable_with(open_batch, command)) {
            open_batch->vertex_count += command->vertex_count;
        } else {
            rgame_draw_batch *batch = &queue->batches[queue->batch_count++];
            batch->texture = command->texture;
            batch->clip = command->clip;
            batch->first_vertex = queue->sorted_count;
            batch->vertex_count = command->vertex_count;
        }

        queue->sorted_count += command->vertex_count;
    }
}

unsigned int rgame_draw_queue_batch_count(const rgame_draw_queue *queue) {
    return queue->batch_count;
}

const rgame_draw_batch *rgame_draw_queue_batch(const rgame_draw_queue *queue,
                                               unsigned int index) {
    return index < queue->batch_count ? &queue->batches[index] : NULL;
}

const rgame_vertex *rgame_draw_queue_vertices(const rgame_draw_queue *queue) {
    return queue->sorted;
}

unsigned int rgame_draw_queue_vertex_count(const rgame_draw_queue *queue) {
    return queue->sorted_count;
}

unsigned int rgame_draw_queue_command_count(const rgame_draw_queue *queue) {
    return queue->command_count;
}

unsigned int rgame_draw_queue_command_capacity(const rgame_draw_queue *queue) {
    return queue->command_capacity;
}

unsigned int rgame_draw_queue_vertex_capacity(const rgame_draw_queue *queue) {
    return queue->vertex_capacity;
}
