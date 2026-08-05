#ifndef RGAME_CLIP_H
#define RGAME_CLIP_H

/*
 * Rectangles and the clip stack — pure arithmetic, no SDL, no GL, no I/O.
 *
 * Clipping restricts drawing to a rectangle. The engine needs it in two very
 * different places: tiling a 9-slice texture's edges without overdraw, and
 * giving each player their own screen region in split-screen. Both want the
 * same thing — a stack where pushing *narrows* the visible area and popping
 * restores it.
 *
 * ---------------------------------------------------------------------------
 * Screen space, and whose job the transform is
 * ---------------------------------------------------------------------------
 *
 * Everything here is in screen pixels. That is deliberate, and it is *not* the
 * whole story for callers: in the layer being replaced, a clip pushed inside a
 * translate moves with it (measured — a clip at x 0..20 inside translate(50,0)
 * clips x 50..70). Reproducing that is the canvas's job: it maps the caller's
 * rect through the current transform and pushes the screen-space result here.
 *
 * Keeping the two apart is what lets this module stay pure integer arithmetic
 * with no idea that transforms exist.
 *
 * ---------------------------------------------------------------------------
 * Empty is a real answer
 * ---------------------------------------------------------------------------
 *
 * Two disjoint rects intersect to nothing, and "nothing" has to be
 * representable — the draw queue uses it to drop commands before they ever
 * reach the GPU. An empty result is canonicalised to {0,0,0,0} so that two
 * different ways of ending up with nothing compare equal, which matters
 * because the clip rect is part of the queue's batch key.
 */

typedef struct {
    int x, y, w, h;
} rgame_rect;

/* Deep enough for any sane scene; a bounded stack cannot run away. */
#define RGAME_CLIP_STACK_DEPTH 32

typedef struct {
    /* entries[0] is the window bounds — the widest anything may draw — so
     * every command has a meaningful clip and there is no "no clip" case. */
    rgame_rect entries[RGAME_CLIP_STACK_DEPTH];
    int depth;
} rgame_clip_stack;

rgame_rect rgame_rect_make(int x, int y, int w, int h);

/* The overlap of two rects, or {0,0,0,0} if they do not overlap. */
rgame_rect rgame_rect_intersect(rgame_rect a, rgame_rect b);

int rgame_rect_is_empty(rgame_rect r);

/* Exact equality. The draw queue compares clips to decide whether two commands
 * can share a batch, so this needs to be cheap and total. */
int rgame_rect_equals(rgame_rect a, rgame_rect b);

int rgame_rect_contains_point(rgame_rect r, int x, int y);

/*
 * Resets the stack with the window bounds as its base. Called at the start of
 * every frame, which is also how a window resize takes effect — there is no
 * separate "the window changed size" path to forget.
 */
void rgame_clip_stack_init(rgame_clip_stack *stack, int width, int height);

/*
 * Narrows the clip to `rect` intersected with the current one, and pushes the
 * result. Returns 1, or 0 if the stack is full — in which case nothing is
 * pushed and no matching pop must be issued.
 *
 * Note this always *narrows*: a pushed rect larger than the current clip
 * cannot widen it. That is what makes nesting safe — a child can never draw
 * outside the region its parent allowed.
 */
int rgame_clip_push(rgame_clip_stack *stack, rgame_rect rect);

/* Pops the current clip. Popping the base is a no-op rather than an underflow. */
void rgame_clip_pop(rgame_clip_stack *stack);

rgame_rect rgame_clip_current(const rgame_clip_stack *stack);
int rgame_clip_is_empty(const rgame_clip_stack *stack);
int rgame_clip_depth(const rgame_clip_stack *stack);

#endif /* RGAME_CLIP_H */
