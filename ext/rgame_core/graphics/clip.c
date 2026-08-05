#include "graphics/clip.h"

/* The canonical empty rect. Every path that produces "nothing" produces this
 * exact value, so two empties compare equal and cannot split a batch. */
static const rgame_rect RGAME_EMPTY_RECT = { 0, 0, 0, 0 };

rgame_rect rgame_rect_make(int x, int y, int w, int h) {
    if (w <= 0 || h <= 0) {
        return RGAME_EMPTY_RECT;
    }
    rgame_rect r = { x, y, w, h };
    return r;
}

int rgame_rect_is_empty(rgame_rect r) {
    return r.w <= 0 || r.h <= 0;
}

int rgame_rect_equals(rgame_rect a, rgame_rect b) {
    return a.x == b.x && a.y == b.y && a.w == b.w && a.h == b.h;
}

int rgame_rect_contains_point(rgame_rect r, int x, int y) {
    return !rgame_rect_is_empty(r) && x >= r.x && y >= r.y && x < r.x + r.w && y < r.y + r.h;
}

rgame_rect rgame_rect_intersect(rgame_rect a, rgame_rect b) {
    if (rgame_rect_is_empty(a) || rgame_rect_is_empty(b)) {
        return RGAME_EMPTY_RECT;
    }

    /*
     * Edges are computed in `long` rather than `int`. A caller can legitimately
     * pass a very large width to mean "as wide as possible", and x + w would
     * then overflow — which is undefined behaviour, not merely a wrong answer.
     * The result always fits back in an int because it is bounded by the
     * smaller of the two inputs.
     */
    long left = a.x > b.x ? a.x : b.x;
    long top = a.y > b.y ? a.y : b.y;
    long a_right = (long)a.x + a.w;
    long b_right = (long)b.x + b.w;
    long a_bottom = (long)a.y + a.h;
    long b_bottom = (long)b.y + b.h;
    long right = a_right < b_right ? a_right : b_right;
    long bottom = a_bottom < b_bottom ? a_bottom : b_bottom;

    if (right <= left || bottom <= top) {
        return RGAME_EMPTY_RECT;
    }

    rgame_rect result = { (int)left, (int)top, (int)(right - left), (int)(bottom - top) };
    return result;
}

void rgame_clip_stack_init(rgame_clip_stack *stack, int width, int height) {
    stack->depth = 0;
    stack->entries[0] = rgame_rect_make(0, 0, width, height);
}

int rgame_clip_push(rgame_clip_stack *stack, rgame_rect rect) {
    if (stack->depth + 1 >= RGAME_CLIP_STACK_DEPTH) {
        return 0;
    }
    stack->entries[stack->depth + 1] =
        rgame_rect_intersect(stack->entries[stack->depth], rect);
    stack->depth++;
    return 1;
}

void rgame_clip_pop(rgame_clip_stack *stack) {
    if (stack->depth > 0) {
        stack->depth--;
    }
}

rgame_rect rgame_clip_current(const rgame_clip_stack *stack) {
    return stack->entries[stack->depth];
}

int rgame_clip_is_empty(const rgame_clip_stack *stack) {
    return rgame_rect_is_empty(stack->entries[stack->depth]);
}

int rgame_clip_depth(const rgame_clip_stack *stack) {
    return stack->depth;
}
