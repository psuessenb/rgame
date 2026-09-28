#ifndef RGAME_TEARDOWN_QUEUE_H
#define RGAME_TEARDOWN_QUEUE_H

#include <stdint.h>

/*
 * Teardowns waiting for the thread that owns what they destroy — pure logic,
 * no SDL, no threads of its own.
 *
 * A window, its GL context and every texture in that context may only be
 * destroyed on the thread that created the app. On Windows, destroying a
 * window from any other thread sends its own thread a message and waits for
 * the answer, and if that thread is waiting too, neither ever moves. A garbage
 * collector breaks the rule without anyone asking it to: Ruby's frees an
 * object on whichever thread happened to allocate, and a spec process that
 * reads a child's output on a second thread froze for twenty minutes at a
 * time before this existed.
 *
 * So a teardown called on the wrong thread is not run but queued, with the id
 * of the thread that must run it, and that thread takes its own entries out at
 * a moment it knows is safe. app.c holds the one queue and the lock around it,
 * and supplies the thread ids; this file only keeps the list.
 */

/* Destroys one object. Runs on the object's own thread. */
typedef void (*rgame_teardown_fn)(void *object);

typedef struct {
    rgame_teardown_fn teardown;
    void *object;
    uint64_t owner_thread;
} rgame_teardown;

/* Zero-initialised is empty and ready to use. */
typedef struct {
    rgame_teardown *entries;
    int count;
    int capacity;
} rgame_teardown_queue;

/*
 * Appends a teardown for `owner_thread` to run. Returns 0, leaving the queue
 * as it was, if memory ran out; the object then leaks, which is the safe
 * failure, since running the teardown here is what must not happen.
 */
int rgame_teardown_queue_push(rgame_teardown_queue *queue, rgame_teardown_fn teardown,
                              void *object, uint64_t owner_thread);

/*
 * Moves every entry for `thread` into `out`, which must be empty, and keeps
 * the rest. Both keep their order. Returns how many moved. Out of memory, it
 * moves nothing and returns 0, and the entries wait for the next take.
 */
int rgame_teardown_queue_take(rgame_teardown_queue *queue, uint64_t thread,
                              rgame_teardown_queue *out);

/* Runs every entry in order, then empties the queue and frees its storage. */
void rgame_teardown_queue_run(rgame_teardown_queue *queue);

/* Frees the storage without running anything. */
void rgame_teardown_queue_free(rgame_teardown_queue *queue);

#endif /* RGAME_TEARDOWN_QUEUE_H */
