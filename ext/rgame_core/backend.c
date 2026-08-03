#include "backend.h"

void rgame_draw_submit(const rgame_draw_queue *queue, const rgame_draw_backend *backend,
                       int width, int height) {
    if (!queue || !backend) {
        return;
    }

    if (backend->begin_frame) {
        backend->begin_frame(backend->ctx, width, height);
    }

    /*
     * Track the clip actually in force rather than assuming each batch needs a
     * fresh one. `have_clip` distinguishes "no clip set yet" from "the current
     * clip happens to equal the zero rect", which a plain comparison against a
     * zeroed variable could not.
     *
     * No batch can currently carry the zero rect — an empty clip makes the
     * queue drop the command before it ever becomes a batch — so the flag is
     * unreachable today, and a test cannot distinguish it. It is kept because
     * the invariant that saves it lives in *another* module: if the queue ever
     * stopped dropping empty-clipped commands, the first batch of a frame would
     * silently go unscissored.
     */
    rgame_rect current_clip = { 0, 0, 0, 0 };
    int have_clip = 0;

    const rgame_vertex *vertices = rgame_draw_queue_vertices(queue);
    unsigned int batches = rgame_draw_queue_batch_count(queue);

    for (unsigned int i = 0; i < batches; i++) {
        const rgame_draw_batch *batch = rgame_draw_queue_batch(queue, i);

        if (!have_clip || !rgame_rect_equals(current_clip, batch->clip)) {
            if (backend->set_clip) {
                backend->set_clip(backend->ctx, batch->clip);
            }
            current_clip = batch->clip;
            have_clip = 1;
        }

        if (backend->draw_batch) {
            backend->draw_batch(backend->ctx, batch->texture, &vertices[batch->first_vertex],
                                batch->vertex_count);
        }
    }

    if (backend->end_frame) {
        backend->end_frame(backend->ctx);
    }
}
