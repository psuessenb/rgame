#include <check.h>

#include "app/teardown_queue.h"
#include "suites.h"

/*
 * The queue that hands a teardown back to the thread that owns its object.
 * Thread ids here are plain numbers: which thread runs the take is app.c's
 * business, and nothing below needs a second thread to check it.
 */

#define THREAD_MAIN 1
#define THREAD_READER 2

/* Each teardown writes its object's number here, in the order it ran. */
static int ran[64];
static int ran_count;

static void record(void *object) {
    ran[ran_count++] = *(int *)object;
}

static void reset_record(void) {
    ran_count = 0;
}

START_TEST(an_empty_queue_takes_nothing_and_allocates_nothing) {
    rgame_teardown_queue queue = { 0 };
    rgame_teardown_queue taken = { 0 };

    ck_assert_int_eq(rgame_teardown_queue_take(&queue, THREAD_MAIN, &taken), 0);
    ck_assert_ptr_null(taken.entries);
    ck_assert_int_eq(taken.count, 0);
}
END_TEST

START_TEST(take_moves_one_threads_entries_and_keeps_the_rest_in_order) {
    int objects[] = { 10, 20, 30, 40, 50 };
    uint64_t owners[] = { THREAD_MAIN, THREAD_READER, THREAD_MAIN, THREAD_READER, THREAD_MAIN };
    rgame_teardown_queue queue = { 0 };
    for (int i = 0; i < 5; i++) {
        ck_assert_int_eq(rgame_teardown_queue_push(&queue, record, &objects[i], owners[i]), 1);
    }

    rgame_teardown_queue taken = { 0 };
    int moved = rgame_teardown_queue_take(&queue, THREAD_MAIN, &taken);

    ck_assert_int_eq(moved, 3);
    ck_assert_int_eq(taken.count, 3);
    ck_assert_ptr_eq(taken.entries[0].object, &objects[0]);
    ck_assert_ptr_eq(taken.entries[1].object, &objects[2]);
    ck_assert_ptr_eq(taken.entries[2].object, &objects[4]);
    ck_assert_int_eq(queue.count, 2);
    ck_assert_ptr_eq(queue.entries[0].object, &objects[1]);
    ck_assert_ptr_eq(queue.entries[1].object, &objects[3]);

    rgame_teardown_queue_free(&taken);
    rgame_teardown_queue_free(&queue);
}
END_TEST

START_TEST(run_calls_every_teardown_in_order_and_empties_the_queue) {
    int objects[] = { 1, 2, 3 };
    rgame_teardown_queue queue = { 0 };
    for (int i = 0; i < 3; i++) {
        rgame_teardown_queue_push(&queue, record, &objects[i], THREAD_MAIN);
    }
    reset_record();

    rgame_teardown_queue_run(&queue);

    ck_assert_int_eq(ran_count, 3);
    ck_assert_int_eq(ran[0], 1);
    ck_assert_int_eq(ran[1], 2);
    ck_assert_int_eq(ran[2], 3);
    ck_assert_int_eq(queue.count, 0);
    ck_assert_ptr_null(queue.entries);
}
END_TEST

START_TEST(a_take_runs_nothing_that_belongs_to_another_thread) {
    int main_object = 1;
    int reader_object = 2;
    rgame_teardown_queue queue = { 0 };
    rgame_teardown_queue_push(&queue, record, &main_object, THREAD_MAIN);
    rgame_teardown_queue_push(&queue, record, &reader_object, THREAD_READER);
    reset_record();

    rgame_teardown_queue taken = { 0 };
    rgame_teardown_queue_take(&queue, THREAD_MAIN, &taken);
    rgame_teardown_queue_run(&taken);

    ck_assert_int_eq(ran_count, 1);
    ck_assert_int_eq(ran[0], 1);
    ck_assert_int_eq(queue.count, 1);
    ck_assert_int_eq(rgame_teardown_queue_take(&queue, THREAD_MAIN, &taken), 0);

    rgame_teardown_queue_free(&queue);
}
END_TEST

START_TEST(the_queue_grows_past_its_first_allocation) {
    int objects[40];
    rgame_teardown_queue queue = { 0 };
    for (int i = 0; i < 40; i++) {
        objects[i] = i;
        ck_assert_int_eq(rgame_teardown_queue_push(&queue, record, &objects[i], THREAD_MAIN), 1);
    }
    reset_record();

    rgame_teardown_queue_run(&queue);

    ck_assert_int_eq(ran_count, 40);
    for (int i = 0; i < 40; i++) {
        ck_assert_int_eq(ran[i], i);
    }
}
END_TEST

Suite *teardown_queue_suite(void) {
    Suite *suite = suite_create("teardown_queue");

    TCase *tc_take = tcase_create("take");
    tcase_add_test(tc_take, an_empty_queue_takes_nothing_and_allocates_nothing);
    tcase_add_test(tc_take, take_moves_one_threads_entries_and_keeps_the_rest_in_order);
    tcase_add_test(tc_take, a_take_runs_nothing_that_belongs_to_another_thread);
    suite_add_tcase(suite, tc_take);

    TCase *tc_run = tcase_create("run");
    tcase_add_test(tc_run, run_calls_every_teardown_in_order_and_empties_the_queue);
    tcase_add_test(tc_run, the_queue_grows_past_its_first_allocation);
    suite_add_tcase(suite, tc_run);

    return suite;
}
