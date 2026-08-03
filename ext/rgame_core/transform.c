#include "transform.h"

#include <math.h>

/* Degrees in, radians out — the C library's trig wants radians, the API takes
 * degrees because that is what Gosu used and what callers already pass. */
#define RGAME_DEGREES_TO_RADIANS (3.14159265358979323846f / 180.0f)

/* Tolerance for "is this the identity". Composing and un-composing transforms
 * accumulates float error, so an exact == would answer "no" for a stack that is
 * identity in every way that matters. */
#define RGAME_IDENTITY_EPSILON 1e-6f

rgame_transform rgame_transform_identity(void) {
    rgame_transform t = { .a = 1.0f, .b = 0.0f, .c = 0.0f, .d = 1.0f, .tx = 0.0f, .ty = 0.0f };
    return t;
}

rgame_transform rgame_transform_multiply(rgame_transform outer, rgame_transform inner) {
    /*
     * Substituting inner's output into outer's formula and collecting terms:
     *
     *   x' = outer.a*(inner.a*x + inner.c*y + inner.tx)
     *      + outer.c*(inner.b*x + inner.d*y + inner.ty) + outer.tx
     *
     * and likewise for y'. Written out rather than looped, because six named
     * multiplies read better than a 2x3 loop and this is the hot path.
     */
    rgame_transform result;
    result.a = (outer.a * inner.a) + (outer.c * inner.b);
    result.b = (outer.b * inner.a) + (outer.d * inner.b);
    result.c = (outer.a * inner.c) + (outer.c * inner.d);
    result.d = (outer.b * inner.c) + (outer.d * inner.d);
    result.tx = (outer.a * inner.tx) + (outer.c * inner.ty) + outer.tx;
    result.ty = (outer.b * inner.tx) + (outer.d * inner.ty) + outer.ty;
    return result;
}

void rgame_transform_stack_init(rgame_transform_stack *stack) {
    stack->depth = 0;
    stack->entries[0] = rgame_transform_identity();
}

/* Shared tail of the three pushes: compose with the current top, store, and
 * report whether there was room. */
static int push_composed(rgame_transform_stack *stack, rgame_transform step) {
    if (stack->depth + 1 >= RGAME_TRANSFORM_STACK_DEPTH) {
        return 0;
    }
    stack->entries[stack->depth + 1] =
        rgame_transform_multiply(stack->entries[stack->depth], step);
    stack->depth++;
    return 1;
}

int rgame_transform_push_translate(rgame_transform_stack *stack, float dx, float dy) {
    rgame_transform step = rgame_transform_identity();
    step.tx = dx;
    step.ty = dy;
    return push_composed(stack, step);
}

int rgame_transform_push_scale(rgame_transform_stack *stack, float sx, float sy) {
    rgame_transform step = rgame_transform_identity();
    step.a = sx;
    step.d = sy;
    return push_composed(stack, step);
}

int rgame_transform_push_rotate(rgame_transform_stack *stack, float degrees,
                                float pivot_x, float pivot_y) {
    float radians = degrees * RGAME_DEGREES_TO_RADIANS;
    float cosine = cosf(radians);
    float sine = sinf(radians);

    /*
     * Rotating about a pivot is three steps: move the pivot to the origin,
     * rotate, move it back. Composed here rather than pushed as three entries,
     * so one push still matches one pop.
     *
     * The rotation itself is the textbook matrix. In screen space, where y
     * points down, it turns *clockwise* for a positive angle — see the header.
     */
    rgame_transform rotation = { .a = cosine, .b = sine, .c = -sine, .d = cosine,
                                 .tx = 0.0f, .ty = 0.0f };

    rgame_transform to_origin = rgame_transform_identity();
    to_origin.tx = -pivot_x;
    to_origin.ty = -pivot_y;

    rgame_transform back = rgame_transform_identity();
    back.tx = pivot_x;
    back.ty = pivot_y;

    rgame_transform step =
        rgame_transform_multiply(back, rgame_transform_multiply(rotation, to_origin));
    return push_composed(stack, step);
}

void rgame_transform_pop(rgame_transform_stack *stack) {
    if (stack->depth > 0) {
        stack->depth--;
    }
}

rgame_transform rgame_transform_current(const rgame_transform_stack *stack) {
    return stack->entries[stack->depth];
}

int rgame_transform_depth(const rgame_transform_stack *stack) {
    return stack->depth;
}

void rgame_transform_apply(const rgame_transform_stack *stack, float x, float y,
                           float *out_x, float *out_y) {
    const rgame_transform *t = &stack->entries[stack->depth];
    *out_x = (t->a * x) + (t->c * y) + t->tx;
    *out_y = (t->b * x) + (t->d * y) + t->ty;
}

int rgame_transform_is_identity(const rgame_transform_stack *stack) {
    const rgame_transform *t = &stack->entries[stack->depth];
    return fabsf(t->a - 1.0f) < RGAME_IDENTITY_EPSILON &&
           fabsf(t->b) < RGAME_IDENTITY_EPSILON &&
           fabsf(t->c) < RGAME_IDENTITY_EPSILON &&
           fabsf(t->d - 1.0f) < RGAME_IDENTITY_EPSILON &&
           fabsf(t->tx) < RGAME_IDENTITY_EPSILON && fabsf(t->ty) < RGAME_IDENTITY_EPSILON;
}
