#include "recording_backend.h"

#include <stdlib.h>
#include <string.h>

/* Test code: an allocation failure here is a broken test run, not a condition
 * worth degrading gracefully for, so growth simply doubles and assumes success
 * the way the rest of the suite does. */
static rgame_recorded_call *next_call(rgame_recording_backend *recorder) {
    if (recorder->count == recorder->capacity) {
        recorder->capacity = recorder->capacity ? recorder->capacity * 2 : 16;
        recorder->calls =
            realloc(recorder->calls, recorder->capacity * sizeof(rgame_recorded_call));
    }
    rgame_recorded_call *call = &recorder->calls[recorder->count++];
    memset(call, 0, sizeof(*call));
    return call;
}

static void record_begin_frame(void *ctx, int width, int height) {
    rgame_recorded_call *call = next_call(ctx);
    call->kind = RGAME_CALL_BEGIN_FRAME;
    call->width = width;
    call->height = height;
}

static void record_set_clip(void *ctx, rgame_rect clip) {
    rgame_recorded_call *call = next_call(ctx);
    call->kind = RGAME_CALL_SET_CLIP;
    call->clip = clip;
}

static void record_draw_batch(void *ctx, unsigned int texture, const rgame_vertex *vertices,
                              unsigned int count) {
    rgame_recording_backend *recorder = ctx;

    if (recorder->vertex_count + count > recorder->vertex_capacity) {
        unsigned int needed = recorder->vertex_count + count;
        unsigned int next = recorder->vertex_capacity ? recorder->vertex_capacity : 64;
        while (next < needed) {
            next *= 2;
        }
        recorder->vertices = realloc(recorder->vertices, next * sizeof(rgame_vertex));
        recorder->vertex_capacity = next;
    }
    memcpy(&recorder->vertices[recorder->vertex_count], vertices,
           count * sizeof(rgame_vertex));

    rgame_recorded_call *call = next_call(recorder);
    call->kind = RGAME_CALL_DRAW_BATCH;
    call->texture = texture;
    call->first_vertex = recorder->vertex_count;
    call->vertex_count = count;
    recorder->vertex_count += count;
}

static void record_end_frame(void *ctx) {
    next_call(ctx)->kind = RGAME_CALL_END_FRAME;
}

void rgame_recording_backend_init(rgame_recording_backend *recorder) {
    memset(recorder, 0, sizeof(*recorder));
}

void rgame_recording_backend_destroy(rgame_recording_backend *recorder) {
    free(recorder->calls);
    free(recorder->vertices);
    memset(recorder, 0, sizeof(*recorder));
}

rgame_draw_backend rgame_recording_backend_interface(rgame_recording_backend *recorder) {
    rgame_draw_backend backend = { .begin_frame = record_begin_frame,
                                   .set_clip = record_set_clip,
                                   .draw_batch = record_draw_batch,
                                   .end_frame = record_end_frame,
                                   .ctx = recorder };
    return backend;
}

unsigned int rgame_recording_call_count(const rgame_recording_backend *recorder) {
    return recorder->count;
}

const rgame_recorded_call *rgame_recording_call(const rgame_recording_backend *recorder,
                                                unsigned int index) {
    return index < recorder->count ? &recorder->calls[index] : NULL;
}

unsigned int rgame_recording_count_of(const rgame_recording_backend *recorder,
                                      rgame_call_kind kind) {
    unsigned int total = 0;
    for (unsigned int i = 0; i < recorder->count; i++) {
        total += recorder->calls[i].kind == kind ? 1 : 0;
    }
    return total;
}

const rgame_vertex *rgame_recording_vertices(const rgame_recording_backend *recorder) {
    return recorder->vertices;
}
