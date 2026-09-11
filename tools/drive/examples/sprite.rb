# Input script for examples/sprite.
#
# Turns the middle sprite one way and then the other, then grows and shrinks it
# to both clamps. Both are axes from the default map, so this drives the arrow
# keys and declares nothing.
#
# What the report should show:
#
#   - **two `image` calls per frame, both at `(0, 0)`**, flat for the entire run.
#     That pair is the whole point of the example: neither Components::Sprite
#     knows where its node is or which way it is facing, and a sprite that spends
#     the run turning and resizing still draws at the origin every frame;
#   - **exactly two distinct translates, and neither ever moves** — (320, 230) for
#     the turntable and (320, 400) for the layered node. The positions are in the
#     transform, pushed once per node per frame, and the report is where "the
#     component passes no position" stops being a claim;
#   - **`rotated` on fewer frames than there are frames.** `Node2D#draw` pushes a
#     rotation only when the node has one, so the opening idle contributes none
#     and the count picks up from the first frame the turn key moves it. It never
#     returns to zero afterwards, because turning back past the start overshoots;
#   - one `image_at` per frame at the fixed corner (24, 60) — the whole sheet,
#     drawn by the scene rather than by a component, through the path id space;
#   - two `rect` calls and four `text` calls per frame, all flat.
#
# Nothing in this scene is ever culled, so no draw count should dip. If one does,
# a footprint is being measured wrongly rather than a sprite being hidden.

idle 10
hold controls::KEY_RIGHT, 45 # turn one way
idle 5
hold controls::KEY_LEFT, 70  # and back past where it started
idle 5

hold controls::KEY_UP, 40    # grow to the clamp
idle 5
hold controls::KEY_DOWN, 55  # shrink past the start, to the other clamp
idle 15
