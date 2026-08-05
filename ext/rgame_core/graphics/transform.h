#ifndef RGAME_TRANSFORM_H
#define RGAME_TRANSFORM_H

/*
 * The 2D affine transform stack — pure arithmetic, no SDL, no GL, no I/O.
 *
 * This is what lets a node spin its whole subtree about its own origin, and
 * what lets a camera shift a world subtree by (-camera_x, -camera_y) without
 * any world-space node knowing a camera exists. Split-screen is the same
 * mechanism used twice in one frame, which is why this is a real stack rather
 * than one "current transform" global.
 *
 * ---------------------------------------------------------------------------
 * What an affine transform is, since this is the first one in the project
 * ---------------------------------------------------------------------------
 *
 * Every operation we need — move, rotate, scale, and any combination — can be
 * written as six numbers applied to a point like this:
 *
 *     x' = a*x + c*y + tx
 *     y' = b*x + d*y + ty
 *
 * `a b c d` are the "linear" part (rotation and scale); `tx ty` are the
 * translation. Six floats, and the same six lines of arithmetic no matter how
 * many transforms are nested — because *composing* two transforms produces
 * another six numbers. That is the whole reason to use matrices here: nesting
 * ten transforms costs the same per-vertex work as nesting one.
 *
 * ---------------------------------------------------------------------------
 * Rotation direction — measured, not assumed
 * ---------------------------------------------------------------------------
 *
 * A positive angle rotates **clockwise on screen**: a point to the right of the
 * pivot moves to below it. That is what the Gosu layer being replaced does,
 * confirmed by rendering `Gosu.rotate(90, ...)` off-screen and reading back
 * which pixel the ink landed on.
 *
 * It falls out of the standard rotation matrix without a sign flip, because
 * screen y points *down*: the same matrix that turns anticlockwise on graph
 * paper turns clockwise here. Worth knowing rather than rediscovering — get it
 * backwards and every rotated sprite in the game mirrors.
 *
 * Angles are degrees, matching Gosu and matching what `Renderer#rotated`
 * callers already pass.
 */

/* Deep enough for any sane scene graph; a bounded stack cannot run away, and
 * an overflow is reported rather than silently scribbling past the end. */
#define RGAME_TRANSFORM_STACK_DEPTH 32

typedef struct {
    float a, b, c, d; /* linear part: rotation and scale */
    float tx, ty;     /* translation */
} rgame_transform;

typedef struct {
    /* entries[0] is always identity — the un-transformed base — so `depth` is
     * the number of pushes outstanding and entries[depth] is the current top. */
    rgame_transform entries[RGAME_TRANSFORM_STACK_DEPTH];
    int depth;
} rgame_transform_stack;

rgame_transform rgame_transform_identity(void);

/*
 * Composition: the result applies `inner` first, then `outer`. That is,
 *
 *     apply(multiply(outer, inner), p) == apply(outer, apply(inner, p))
 *
 * which is the order nesting reads in: in `translated { rotated { draw } }`
 * the rotation happens to the point first and the translation moves the
 * already-rotated result.
 */
rgame_transform rgame_transform_multiply(rgame_transform outer, rgame_transform inner);

void rgame_transform_stack_init(rgame_transform_stack *stack);

/*
 * Each push composes with the current top and pushes the *result*, so `apply`
 * stays a single six-multiply operation however deep the nesting goes.
 *
 * All three return 1 on success and 0 if the stack is full. A full stack leaves
 * the existing entries untouched — the caller's drawing comes out unrotated
 * rather than corrupt — but it does mean a matching pop must not be issued, so
 * check the return value if the depth is not statically known.
 */
int rgame_transform_push_translate(rgame_transform_stack *stack, float dx, float dy);
int rgame_transform_push_rotate(rgame_transform_stack *stack, float degrees,
                                float pivot_x, float pivot_y);
int rgame_transform_push_scale(rgame_transform_stack *stack, float sx, float sy);

/* Pops the current top. Popping the base is a no-op rather than an underflow. */
void rgame_transform_pop(rgame_transform_stack *stack);

rgame_transform rgame_transform_current(const rgame_transform_stack *stack);
int rgame_transform_depth(const rgame_transform_stack *stack);

/* Maps a point through the current top. This is the per-vertex hot path. */
void rgame_transform_apply(const rgame_transform_stack *stack, float x, float y,
                           float *out_x, float *out_y);

/* Whether the current top would leave every point where it is. Lets a caller
 * skip work that would be a no-op — the common case for un-transformed draws. */
int rgame_transform_is_identity(const rgame_transform_stack *stack);

#endif /* RGAME_TRANSFORM_H */
