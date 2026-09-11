# Input script for examples/velocity.
#
# Walks the circle out through the left edge of the world, then the top, then
# back across the diagonal — so the wrap can be watched happening to the node
# being driven as well as to the five that are not.
#
# What the report should show:
#
#   - **translates spanning x -40..500 and y -40..370**, which is the whole
#     argument of the example in two numbers. The world is 460x330 and the wrap
#     margin is 40, so those are exactly `0 - margin` to `size + margin` on each
#     axis. The window is 640x480 and nothing ever reaches it: the bounds being
#     used are the ones the scene's `Components::World` declares, not the
#     viewport's;
#   - **translates still changing through every idle stretch.** Five of the six
#     moving nodes are never touched by this script and advance on every frame of
#     it. A velocity needs nobody;
#   - **eleven `rect` calls per frame, flat** — the backdrop, the floor, four edge
#     pieces and one per drifter. A wrap relocates a node; it never adds or drops
#     a draw, so a dip here would mean a node had stopped being reached;
#   - **two `rotated` pushes per frame**, because two of the five drifters carry a
#     spin and `Node2D#draw` pushes a rotation only for a node whose angle is not
#     zero. The count comes in two short of twice the frames, since both start at
#     zero and are still there on the first;
#   - one `circle` and three `text` calls per frame;
#   - **no clips at all.** The world being smaller than the window is an offset
#     and a rectangle, not a viewport.
#
# Nothing here needs a seed: the drifters' velocities are a fixed table, so two
# runs at the same tick budget produce the same numbers.

idle 20
hold controls::KEY_LEFT, 80  # out through the left edge of the world
idle 10
hold controls::KEY_UP, 70    # and up through the top
idle 10
hold [controls::KEY_RIGHT, controls::KEY_DOWN], 60 # back across the diagonal
idle 30
