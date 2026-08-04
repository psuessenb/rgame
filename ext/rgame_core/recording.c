/*
 * recording.c — copying a prepared frame out of the queue and keeping it.
 * See recording.h for what a recording is for and what it does not capture.
 */

#include "recording.h"

#include <stdlib.h>
#include <string.h>

void rgame_recording_destroy(rgame_recording *recording) {
    if (!recording) {
        return;
    }

    free(recording->vertices);
    free(recording->batches);
    /* Zeroed rather than merely freed, so a second destroy is a no-op and a
     * replay after destroy draws nothing instead of reading freed memory. */
    recording->vertices = NULL;
    recording->batches = NULL;
    recording->vertex_count = 0;
    recording->batch_count = 0;
}

int rgame_recording_capture(rgame_recording *out, const rgame_draw_queue *queue) {
    if (!out || !queue) {
        return 0;
    }

    out->vertices = NULL;
    out->batches = NULL;
    out->vertex_count = 0;
    out->batch_count = 0;

    unsigned int batch_count = rgame_draw_queue_batch_count(queue);
    unsigned int vertex_count = rgame_draw_queue_vertex_count(queue);
    if (batch_count == 0 || vertex_count == 0) {
        return 1; /* nothing was drawn; an empty recording is a valid one */
    }

    /* Exact allocations, not the queue's growth strategy: a recording is
     * written once and read for the rest of the level, so the spare capacity
     * that makes a per-frame queue cheap would just be a level-long leak. */
    rgame_vertex *vertices = malloc(sizeof(rgame_vertex) * vertex_count);
    rgame_recording_batch *batches = malloc(sizeof(rgame_recording_batch) * batch_count);
    if (!vertices || !batches) {
        free(vertices);
        free(batches);
        return 0;
    }

    memcpy(vertices, rgame_draw_queue_vertices(queue), sizeof(rgame_vertex) * vertex_count);

    /*
     * The queue's batches carry a clip as well; only the texture and the span
     * come across. See recording.h — a clip recorded at one place on screen is
     * wrong at every other place the recording is replayed.
     */
    for (unsigned int i = 0; i < batch_count; i++) {
        const rgame_draw_batch *source = rgame_draw_queue_batch(queue, i);
        batches[i].texture = source->texture;
        batches[i].first_vertex = source->first_vertex;
        batches[i].vertex_count = source->vertex_count;
    }

    out->vertices = vertices;
    out->vertex_count = vertex_count;
    out->batches = batches;
    out->batch_count = batch_count;
    return 1;
}

unsigned int rgame_recording_batch_count(const rgame_recording *recording) {
    return recording ? recording->batch_count : 0;
}

unsigned int rgame_recording_vertex_count(const rgame_recording *recording) {
    return recording ? recording->vertex_count : 0;
}

void rgame_recording_bounds(const rgame_recording *recording, float *min_x, float *min_y,
                            float *max_x, float *max_y) {
    float left = 0.0f, top = 0.0f, right = 0.0f, bottom = 0.0f;

    if (recording && recording->vertex_count > 0) {
        left = right = recording->vertices[0].x;
        top = bottom = recording->vertices[0].y;

        for (unsigned int i = 1; i < recording->vertex_count; i++) {
            const rgame_vertex *vertex = &recording->vertices[i];
            if (vertex->x < left) {
                left = vertex->x;
            }
            if (vertex->x > right) {
                right = vertex->x;
            }
            if (vertex->y < top) {
                top = vertex->y;
            }
            if (vertex->y > bottom) {
                bottom = vertex->y;
            }
        }
    }

    if (min_x) {
        *min_x = left;
    }
    if (min_y) {
        *min_y = top;
    }
    if (max_x) {
        *max_x = right;
    }
    if (max_y) {
        *max_y = bottom;
    }
}
