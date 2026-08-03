#include <check.h>

#include "draw_queue.h"
#include "suites.h"

/*
 * The queue is exercised directly: fill it with commands, prepare, and read the
 * batches back. No backend, no fake, no display — the whole module is
 * arithmetic over plain arrays.
 */

static rgame_rect full_clip(void) {
    return rgame_rect_make(0, 0, 800, 600);
}

/* Push one 3-vertex primitive whose first vertex x is `tag`, so the sorted
 * output can be read back and identified. */
static void push_tagged(rgame_draw_queue *q, float tag, double z, unsigned int texture,
                        rgame_rect clip) {
    rgame_vertex *v = rgame_draw_queue_alloc(q, 3, z, texture, clip);
    for (int i = 0; i < 3; i++) {
        v[i].x = tag;
        v[i].y = 0.0f;
        v[i].u = 0.0f;
        v[i].v = 0.0f;
        v[i].rgba[0] = 255;
        v[i].rgba[1] = 255;
        v[i].rgba[2] = 255;
        v[i].rgba[3] = 255;
    }
}

/* The tag of the primitive occupying sorted vertex slot `n * 3`. */
static float tag_at(const rgame_draw_queue *q, unsigned int primitive_index) {
    return rgame_draw_queue_vertices(q)[primitive_index * 3].x;
}

/* --- ordering --- */

START_TEST(commands_come_out_in_ascending_z) {
    rgame_draw_queue q;
    rgame_draw_queue_init(&q);

    push_tagged(&q, 30.0f, 3.0, 0, full_clip());
    push_tagged(&q, 10.0f, 1.0, 0, full_clip());
    push_tagged(&q, 20.0f, 2.0, 0, full_clip());
    rgame_draw_queue_prepare(&q);

    ck_assert_float_eq(tag_at(&q, 0), 10.0f);
    ck_assert_float_eq(tag_at(&q, 1), 20.0f);
    ck_assert_float_eq(tag_at(&q, 2), 30.0f);

    rgame_draw_queue_destroy(&q);
}
END_TEST

START_TEST(equal_z_keeps_the_order_the_calls_were_made_in) {
    /*
     * Gosu breaks z ties by call order, and so must this. Without the tiebreak
     * the sort is free to reshuffle equal-z commands from frame to frame, which
     * shows up as same-z sprites flickering past each other.
     */
    rgame_draw_queue q;
    rgame_draw_queue_init(&q);

    for (int i = 0; i < 8; i++) {
        push_tagged(&q, (float)i, 5.0, 0, full_clip());
    }
    rgame_draw_queue_prepare(&q);

    for (unsigned int i = 0; i < 8; i++) {
        ck_assert_float_eq(tag_at(&q, i), (float)i);
    }

    rgame_draw_queue_destroy(&q);
}
END_TEST

START_TEST(a_lower_z_issued_last_still_draws_first) {
    /* The property the whole module exists for: draw order does not decide
     * paint order, z does. */
    rgame_draw_queue q;
    rgame_draw_queue_init(&q);

    push_tagged(&q, 99.0f, 10.0, 0, full_clip()); /* issued first, on top */
    push_tagged(&q, 11.0f, -5.0, 0, full_clip()); /* issued last, behind */
    rgame_draw_queue_prepare(&q);

    ck_assert_float_eq(tag_at(&q, 0), 11.0f);
    ck_assert_float_eq(tag_at(&q, 1), 99.0f);

    rgame_draw_queue_destroy(&q);
}
END_TEST

START_TEST(negative_and_fractional_z_sort_correctly) {
    rgame_draw_queue q;
    rgame_draw_queue_init(&q);

    push_tagged(&q, 3.0f, 0.5, 0, full_clip());
    push_tagged(&q, 1.0f, -100.25, 0, full_clip());
    push_tagged(&q, 2.0f, 0.25, 0, full_clip());
    rgame_draw_queue_prepare(&q);

    ck_assert_float_eq(tag_at(&q, 0), 1.0f);
    ck_assert_float_eq(tag_at(&q, 1), 2.0f);
    ck_assert_float_eq(tag_at(&q, 2), 3.0f);

    rgame_draw_queue_destroy(&q);
}
END_TEST

START_TEST(a_nan_z_does_not_corrupt_the_sort) {
    /* qsort with a comparator that does not impose a total order is undefined
     * behaviour, and NaN compares false against everything. It is coerced on
     * the way in so a stray NaN degrades to "drawn at z 0", not to chaos. */
    rgame_draw_queue q;
    rgame_draw_queue_init(&q);

    /*
     * The NaN command is issued *first* but given a z that, once coerced to 0,
     * must place it *after* the negative-z one. Without the coercion the
     * comparator falls through to insertion order and the NaN command would
     * sort first — so this distinguishes "guard present" from "guard absent",
     * which comparing against a positive z would not.
     */
    double nan_z = 0.0 / 0.0;
    push_tagged(&q, 1.0f, nan_z, 0, full_clip());
    push_tagged(&q, 2.0f, -5.0, 0, full_clip());
    rgame_draw_queue_prepare(&q);

    ck_assert_uint_eq(rgame_draw_queue_command_count(&q), 2);
    ck_assert_float_eq(tag_at(&q, 0), 2.0f); /* z -5 */
    ck_assert_float_eq(tag_at(&q, 1), 1.0f); /* NaN, coerced to z 0 */

    rgame_draw_queue_destroy(&q);
}
END_TEST

/* --- the ordering rule, tested directly --- */

static rgame_draw_command cmd(double z, unsigned int order) {
    rgame_draw_command c;
    c.z = z;
    c.order = order;
    c.texture = 0;
    c.clip = full_clip();
    c.first_vertex = 0;
    c.vertex_count = 0;
    return c;
}

START_TEST(the_comparator_orders_by_z_then_insertion) {
    /*
     * Tested directly rather than through the sort: glibc's qsort happens to be
     * stable, so dropping the insertion-order tiebreak would still produce the
     * right answer *here* while leaving the order undefined on any library
     * whose qsort is not. The comparator is the contract; the sort just uses it.
     */
    rgame_draw_command low = cmd(1.0, 5);
    rgame_draw_command high = cmd(2.0, 0);
    ck_assert_int_lt(rgame_draw_command_compare(&low, &high), 0);
    ck_assert_int_gt(rgame_draw_command_compare(&high, &low), 0);

    rgame_draw_command first = cmd(1.0, 0);
    rgame_draw_command second = cmd(1.0, 1);
    ck_assert_int_lt(rgame_draw_command_compare(&first, &second), 0);
    ck_assert_int_gt(rgame_draw_command_compare(&second, &first), 0);

    /* Only a command compared with itself is "equal" — the order field is
     * unique, so the relation is a total order and any sort gives one answer. */
    ck_assert_int_eq(rgame_draw_command_compare(&first, &first), 0);
}
END_TEST

/* --- batching --- */

START_TEST(commands_sharing_a_texture_and_clip_become_one_batch) {
    rgame_draw_queue q;
    rgame_draw_queue_init(&q);

    push_tagged(&q, 1.0f, 1.0, 7, full_clip());
    push_tagged(&q, 2.0f, 2.0, 7, full_clip());
    push_tagged(&q, 3.0f, 3.0, 7, full_clip());
    rgame_draw_queue_prepare(&q);

    ck_assert_uint_eq(rgame_draw_queue_batch_count(&q), 1);
    const rgame_draw_batch *b = rgame_draw_queue_batch(&q, 0);
    ck_assert_uint_eq(b->texture, 7);
    ck_assert_uint_eq(b->first_vertex, 0);
    ck_assert_uint_eq(b->vertex_count, 9);

    rgame_draw_queue_destroy(&q);
}
END_TEST

START_TEST(a_texture_change_splits_a_batch) {
    rgame_draw_queue q;
    rgame_draw_queue_init(&q);

    push_tagged(&q, 1.0f, 1.0, 7, full_clip());
    push_tagged(&q, 2.0f, 2.0, 9, full_clip());
    rgame_draw_queue_prepare(&q);

    ck_assert_uint_eq(rgame_draw_queue_batch_count(&q), 2);
    ck_assert_uint_eq(rgame_draw_queue_batch(&q, 0)->texture, 7);
    ck_assert_uint_eq(rgame_draw_queue_batch(&q, 1)->texture, 9);

    rgame_draw_queue_destroy(&q);
}
END_TEST

START_TEST(a_clip_change_splits_a_batch) {
    /* Two commands with the same texture but different scissor rects cannot
     * share a draw call, or one would be clipped by the other's rect. */
    rgame_draw_queue q;
    rgame_draw_queue_init(&q);

    push_tagged(&q, 1.0f, 1.0, 7, rgame_rect_make(0, 0, 400, 600));
    push_tagged(&q, 2.0f, 2.0, 7, rgame_rect_make(400, 0, 400, 600));
    rgame_draw_queue_prepare(&q);

    ck_assert_uint_eq(rgame_draw_queue_batch_count(&q), 2);
    ck_assert_int_eq(rgame_draw_queue_batch(&q, 0)->clip.x, 0);
    ck_assert_int_eq(rgame_draw_queue_batch(&q, 1)->clip.x, 400);

    rgame_draw_queue_destroy(&q);
}
END_TEST

START_TEST(batching_happens_after_sorting_not_before) {
    /*
     * The interesting case. Issued as A, B, A — but with z values that sort
     * them A, A, B. Batching the *issued* order would give three batches;
     * batching the *sorted* order gives two, which is the whole point of
     * doing it here rather than at the call site.
     */
    rgame_draw_queue q;
    rgame_draw_queue_init(&q);

    push_tagged(&q, 1.0f, 1.0, 7, full_clip());
    push_tagged(&q, 2.0f, 9.0, 9, full_clip());
    push_tagged(&q, 3.0f, 2.0, 7, full_clip());
    rgame_draw_queue_prepare(&q);

    ck_assert_uint_eq(rgame_draw_queue_batch_count(&q), 2);
    const rgame_draw_batch *first = rgame_draw_queue_batch(&q, 0);
    ck_assert_uint_eq(first->texture, 7);
    ck_assert_uint_eq(first->vertex_count, 6); /* both texture-7 commands */
    ck_assert_uint_eq(rgame_draw_queue_batch(&q, 1)->texture, 9);

    rgame_draw_queue_destroy(&q);
}
END_TEST

START_TEST(a_batch_returning_to_an_earlier_texture_is_a_new_batch) {
    /* Only *adjacent* commands merge; A B A stays three draws. Merging
     * non-adjacent ones would reorder across B and break the z ordering. */
    rgame_draw_queue q;
    rgame_draw_queue_init(&q);

    push_tagged(&q, 1.0f, 1.0, 7, full_clip());
    push_tagged(&q, 2.0f, 2.0, 9, full_clip());
    push_tagged(&q, 3.0f, 3.0, 7, full_clip());
    rgame_draw_queue_prepare(&q);

    ck_assert_uint_eq(rgame_draw_queue_batch_count(&q), 3);

    rgame_draw_queue_destroy(&q);
}
END_TEST

START_TEST(batch_vertex_ranges_are_contiguous_and_cover_everything) {
    rgame_draw_queue q;
    rgame_draw_queue_init(&q);

    push_tagged(&q, 1.0f, 1.0, 7, full_clip());
    push_tagged(&q, 2.0f, 2.0, 9, full_clip());
    push_tagged(&q, 3.0f, 3.0, 9, full_clip());
    rgame_draw_queue_prepare(&q);

    unsigned int expected_start = 0;
    for (unsigned int i = 0; i < rgame_draw_queue_batch_count(&q); i++) {
        const rgame_draw_batch *b = rgame_draw_queue_batch(&q, i);
        ck_assert_uint_eq(b->first_vertex, expected_start);
        expected_start += b->vertex_count;
    }
    ck_assert_uint_eq(expected_start, rgame_draw_queue_vertex_count(&q));
    ck_assert_uint_eq(expected_start, 9);

    rgame_draw_queue_destroy(&q);
}
END_TEST

/* --- dropping --- */

START_TEST(an_empty_clip_drops_the_command) {
    rgame_draw_queue q;
    rgame_draw_queue_init(&q);

    push_tagged(&q, 1.0f, 1.0, 0, rgame_rect_make(0, 0, 0, 0));
    rgame_draw_queue_prepare(&q);

    ck_assert_uint_eq(rgame_draw_queue_command_count(&q), 0);
    ck_assert_uint_eq(rgame_draw_queue_batch_count(&q), 0);

    rgame_draw_queue_destroy(&q);
}
END_TEST

START_TEST(a_dropped_command_still_returns_somewhere_writable) {
    /*
     * The caller fills the span it is handed without checking anything, so a
     * dropped command must return real memory rather than NULL — a forgotten
     * check should mean an invisible draw, not a segfault. Writing through it
     * here is the test: under the sanitizer build this fails loudly if the
     * span is bogus.
     */
    rgame_draw_queue q;
    rgame_draw_queue_init(&q);

    rgame_vertex *span = rgame_draw_queue_alloc(&q, 6, 0.0, 0, rgame_rect_make(0, 0, 0, 0));
    ck_assert_ptr_nonnull(span);
    for (int i = 0; i < 6; i++) {
        span[i].x = 1.0f;
        span[i].rgba[3] = 255;
    }

    ck_assert_uint_eq(rgame_draw_queue_command_count(&q), 0);

    rgame_draw_queue_destroy(&q);
}
END_TEST

START_TEST(a_zero_vertex_command_is_dropped) {
    rgame_draw_queue q;
    rgame_draw_queue_init(&q);

    rgame_vertex *span = rgame_draw_queue_alloc(&q, 0, 1.0, 0, full_clip());
    ck_assert_ptr_nonnull(span);
    ck_assert_uint_eq(rgame_draw_queue_command_count(&q), 0);

    rgame_draw_queue_destroy(&q);
}
END_TEST

START_TEST(dropped_commands_do_not_disturb_the_ones_that_survive) {
    rgame_draw_queue q;
    rgame_draw_queue_init(&q);

    push_tagged(&q, 1.0f, 1.0, 0, full_clip());
    push_tagged(&q, 99.0f, 2.0, 0, rgame_rect_make(0, 0, 0, 0)); /* dropped */
    push_tagged(&q, 2.0f, 3.0, 0, full_clip());
    rgame_draw_queue_prepare(&q);

    ck_assert_uint_eq(rgame_draw_queue_command_count(&q), 2);
    ck_assert_float_eq(tag_at(&q, 0), 1.0f);
    ck_assert_float_eq(tag_at(&q, 1), 2.0f);

    rgame_draw_queue_destroy(&q);
}
END_TEST

/* --- the frame cycle --- */

START_TEST(an_empty_queue_prepares_to_nothing) {
    rgame_draw_queue q;
    rgame_draw_queue_init(&q);
    rgame_draw_queue_prepare(&q);

    ck_assert_uint_eq(rgame_draw_queue_batch_count(&q), 0);
    ck_assert_uint_eq(rgame_draw_queue_vertex_count(&q), 0);
    ck_assert_ptr_null(rgame_draw_queue_batch(&q, 0));

    rgame_draw_queue_destroy(&q);
}
END_TEST

START_TEST(reset_empties_the_queue_without_giving_back_the_buffers) {
    /*
     * The no-per-frame-allocation property, made visible. A renderer that
     * reallocates every frame is a stutter waiting to happen, and nothing else
     * in the suite would notice it — hence asserting on capacity.
     */
    rgame_draw_queue q;
    rgame_draw_queue_init(&q);

    for (int i = 0; i < 50; i++) {
        push_tagged(&q, (float)i, (double)i, 0, full_clip());
    }
    rgame_draw_queue_prepare(&q);

    unsigned int commands = rgame_draw_queue_command_capacity(&q);
    unsigned int vertices = rgame_draw_queue_vertex_capacity(&q);
    ck_assert_uint_gt(commands, 0);

    rgame_draw_queue_reset(&q);
    ck_assert_uint_eq(rgame_draw_queue_command_count(&q), 0);
    /* Checked here, immediately: regrowing to the same size by coincidence
     * would look identical if only the end state were compared. */
    ck_assert_uint_eq(rgame_draw_queue_command_capacity(&q), commands);
    ck_assert_uint_eq(rgame_draw_queue_vertex_capacity(&q), vertices);

    /* An identical second frame must not grow anything. */
    for (int i = 0; i < 50; i++) {
        push_tagged(&q, (float)i, (double)i, 0, full_clip());
    }
    rgame_draw_queue_prepare(&q);

    ck_assert_uint_eq(rgame_draw_queue_command_capacity(&q), commands);
    ck_assert_uint_eq(rgame_draw_queue_vertex_capacity(&q), vertices);
    ck_assert_uint_eq(rgame_draw_queue_batch_count(&q), 1);

    rgame_draw_queue_destroy(&q);
}
END_TEST

START_TEST(a_second_frame_sorts_independently_of_the_first) {
    rgame_draw_queue q;
    rgame_draw_queue_init(&q);

    push_tagged(&q, 1.0f, 1.0, 0, full_clip());
    rgame_draw_queue_prepare(&q);
    rgame_draw_queue_reset(&q);

    push_tagged(&q, 7.0f, 5.0, 0, full_clip());
    push_tagged(&q, 8.0f, 4.0, 0, full_clip());
    rgame_draw_queue_prepare(&q);

    ck_assert_uint_eq(rgame_draw_queue_vertex_count(&q), 6);
    ck_assert_float_eq(tag_at(&q, 0), 8.0f);
    ck_assert_float_eq(tag_at(&q, 1), 7.0f);

    rgame_draw_queue_destroy(&q);
}
END_TEST

START_TEST(vertex_contents_survive_the_sort_intact) {
    /* Sorting moves whole primitives, so a command's vertices must stay
     * together and keep their values — not just their first one. */
    rgame_draw_queue q;
    rgame_draw_queue_init(&q);

    rgame_vertex *late = rgame_draw_queue_alloc(&q, 3, 9.0, 0, full_clip());
    for (int i = 0; i < 3; i++) {
        late[i].x = 100.0f + i;
        late[i].y = 200.0f + i;
        late[i].u = 0.5f;
        late[i].v = 0.25f;
        late[i].rgba[0] = 10;
        late[i].rgba[1] = 20;
        late[i].rgba[2] = 30;
        late[i].rgba[3] = 40;
    }
    push_tagged(&q, 1.0f, 1.0, 0, full_clip());
    rgame_draw_queue_prepare(&q);

    const rgame_vertex *out = rgame_draw_queue_vertices(&q);
    for (int i = 0; i < 3; i++) {
        const rgame_vertex *v = &out[3 + i]; /* the z=9 command sorted second */
        ck_assert_float_eq(v->x, 100.0f + i);
        ck_assert_float_eq(v->y, 200.0f + i);
        ck_assert_float_eq(v->u, 0.5f);
        ck_assert_float_eq(v->v, 0.25f);
        ck_assert_uint_eq(v->rgba[0], 10);
        ck_assert_uint_eq(v->rgba[3], 40);
    }

    rgame_draw_queue_destroy(&q);
}
END_TEST

START_TEST(destroy_leaves_a_queue_that_can_be_initialised_again) {
    rgame_draw_queue q;
    rgame_draw_queue_init(&q);
    push_tagged(&q, 1.0f, 1.0, 0, full_clip());
    rgame_draw_queue_destroy(&q);

    /* Destroy zeroes the struct, so a second destroy frees nothing twice —
     * the sanitizer build is what proves that. */
    rgame_draw_queue_destroy(&q);

    rgame_draw_queue_init(&q);
    push_tagged(&q, 2.0f, 1.0, 0, full_clip());
    rgame_draw_queue_prepare(&q);
    ck_assert_uint_eq(rgame_draw_queue_batch_count(&q), 1);

    rgame_draw_queue_destroy(&q);
}
END_TEST

START_TEST(growing_past_the_initial_capacity_keeps_everything) {
    /* Force several doublings and check nothing is lost or duplicated. */
    rgame_draw_queue q;
    rgame_draw_queue_init(&q);

    const int count = 500;
    for (int i = 0; i < count; i++) {
        push_tagged(&q, (float)i, (double)(count - i), 0, full_clip());
    }
    rgame_draw_queue_prepare(&q);

    ck_assert_uint_eq(rgame_draw_queue_command_count(&q), (unsigned int)count);
    ck_assert_uint_eq(rgame_draw_queue_vertex_count(&q), (unsigned int)count * 3);
    /* z descends as the tag ascends, so the sorted order is reversed. */
    ck_assert_float_eq(tag_at(&q, 0), (float)(count - 1));
    ck_assert_float_eq(tag_at(&q, (unsigned int)count - 1), 0.0f);

    rgame_draw_queue_destroy(&q);
}
END_TEST

START_TEST(batch_offsets_index_the_sorted_array_not_the_submitted_one) {
    /*
     * Submitted z-descending so sorting genuinely reorders: the command that
     * ends up first was submitted last and sits at the *end* of the unsubmitted
     * vertex array. A batch offset taken from the command rather than from the
     * output position would point at the wrong vertices — and would look
     * correct in any test where draw order already matched z order.
     */
    rgame_draw_queue q;
    rgame_draw_queue_init(&q);

    push_tagged(&q, 1.0f, 9.0, 7, full_clip());
    push_tagged(&q, 2.0f, 5.0, 9, full_clip());
    push_tagged(&q, 3.0f, 1.0, 8, full_clip());
    rgame_draw_queue_prepare(&q);

    ck_assert_uint_eq(rgame_draw_queue_batch_count(&q), 3);
    ck_assert_uint_eq(rgame_draw_queue_batch(&q, 0)->first_vertex, 0);
    ck_assert_uint_eq(rgame_draw_queue_batch(&q, 1)->first_vertex, 3);
    ck_assert_uint_eq(rgame_draw_queue_batch(&q, 2)->first_vertex, 6);

    /* And each batch's range really does hold that command's vertices. */
    const rgame_vertex *v = rgame_draw_queue_vertices(&q);
    ck_assert_float_eq(v[rgame_draw_queue_batch(&q, 0)->first_vertex].x, 3.0f);
    ck_assert_float_eq(v[rgame_draw_queue_batch(&q, 1)->first_vertex].x, 2.0f);
    ck_assert_float_eq(v[rgame_draw_queue_batch(&q, 2)->first_vertex].x, 1.0f);

    rgame_draw_queue_destroy(&q);
}
END_TEST

START_TEST(preparing_twice_without_a_reset_is_idempotent) {
    /* A double flush must not append a second copy of every batch. */
    rgame_draw_queue q;
    rgame_draw_queue_init(&q);

    push_tagged(&q, 1.0f, 1.0, 7, full_clip());
    push_tagged(&q, 2.0f, 2.0, 9, full_clip());

    rgame_draw_queue_prepare(&q);
    unsigned int batches = rgame_draw_queue_batch_count(&q);
    unsigned int vertices = rgame_draw_queue_vertex_count(&q);

    rgame_draw_queue_prepare(&q);

    ck_assert_uint_eq(rgame_draw_queue_batch_count(&q), batches);
    ck_assert_uint_eq(rgame_draw_queue_vertex_count(&q), vertices);
    ck_assert_float_eq(tag_at(&q, 0), 1.0f);

    rgame_draw_queue_destroy(&q);
}
END_TEST

Suite *draw_queue_suite(void) {
    Suite *suite = suite_create("draw_queue");

    TCase *tc_order = tcase_create("ordering");
    tcase_add_test(tc_order, commands_come_out_in_ascending_z);
    tcase_add_test(tc_order, equal_z_keeps_the_order_the_calls_were_made_in);
    tcase_add_test(tc_order, a_lower_z_issued_last_still_draws_first);
    tcase_add_test(tc_order, negative_and_fractional_z_sort_correctly);
    tcase_add_test(tc_order, a_nan_z_does_not_corrupt_the_sort);
    tcase_add_test(tc_order, the_comparator_orders_by_z_then_insertion);
    suite_add_tcase(suite, tc_order);

    TCase *tc_batch = tcase_create("batching");
    tcase_add_test(tc_batch, commands_sharing_a_texture_and_clip_become_one_batch);
    tcase_add_test(tc_batch, a_texture_change_splits_a_batch);
    tcase_add_test(tc_batch, a_clip_change_splits_a_batch);
    tcase_add_test(tc_batch, batching_happens_after_sorting_not_before);
    tcase_add_test(tc_batch, a_batch_returning_to_an_earlier_texture_is_a_new_batch);
    tcase_add_test(tc_batch, batch_vertex_ranges_are_contiguous_and_cover_everything);
    tcase_add_test(tc_batch, batch_offsets_index_the_sorted_array_not_the_submitted_one);
    suite_add_tcase(suite, tc_batch);

    TCase *tc_drop = tcase_create("dropping");
    tcase_add_test(tc_drop, an_empty_clip_drops_the_command);
    tcase_add_test(tc_drop, a_dropped_command_still_returns_somewhere_writable);
    tcase_add_test(tc_drop, a_zero_vertex_command_is_dropped);
    tcase_add_test(tc_drop, dropped_commands_do_not_disturb_the_ones_that_survive);
    suite_add_tcase(suite, tc_drop);

    TCase *tc_frame = tcase_create("frame_cycle");
    tcase_add_test(tc_frame, an_empty_queue_prepares_to_nothing);
    tcase_add_test(tc_frame, reset_empties_the_queue_without_giving_back_the_buffers);
    tcase_add_test(tc_frame, a_second_frame_sorts_independently_of_the_first);
    tcase_add_test(tc_frame, vertex_contents_survive_the_sort_intact);
    tcase_add_test(tc_frame, destroy_leaves_a_queue_that_can_be_initialised_again);
    tcase_add_test(tc_frame, growing_past_the_initial_capacity_keeps_everything);
    tcase_add_test(tc_frame, preparing_twice_without_a_reset_is_idempotent);
    suite_add_tcase(suite, tc_frame);

    return suite;
}
