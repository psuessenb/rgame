# Input script for examples/collision_tiles: the spiky ball.
#
# The other script for this example (`collision_tiles.rb`) holds down and left
# and never goes near the ball. This one goes straight at it: east into the ball,
# west away from it, then east into it again, which is the only sequence that
# shows what the two signals are for.
#
# The hero starts at x 384 with its feet box three tiles west of the ball's, so
# the first stretch of walking is free and the rest of it is spent pressed
# against something.
#
# What the report should show:
#
#   - **`text` ending on `"Lives: 1"`**, which is the acceptance test. Three
#     lives, two arrivals at the ball, one life each. The label is the last text
#     drawn each frame, so the run's last `text` argument is the count it ended
#     on — and the first is the help line the first frame opened with;
#   - **one life per arrival, not one per frame.** Forty-odd of these ticks are
#     spent pushing into a ball that is already stopping the hero, and they cost
#     nothing: `on_blocked` fires on the step it starts. Backing off fires
#     `on_unblocked`, which is what arms the second one;
#   - **one `circle` and two `line` calls per frame** — the ball, drawn in its own
#     local space, so its arguments never vary;
#   - **one `sprite` and one `rect` per frame**, the hero and its feet box, the
#     rect at `(2, 16, 12, 6)` in every frame because a collision box is stated in
#     the node's own space;
#   - **translates spanning a narrow band in y.** The hero walks east and west
#     along one row and never leaves it, so the camera track moves in x and holds
#     in y — the opposite signature to the other script's;
#   - **two `tilemap` calls per frame** (the ground and the obstacles) and **two
#     clips**, both the full window: the WorldView's camera and the
#     presentation's letterbox, coinciding because one player fills the window.
#
# Nothing here needs a seed — the map is a file and the timestep is fixed.

idle 10
hold controls::KEY_RIGHT, 45 # into the ball, then pushing into it: one life
hold controls::KEY_LEFT, 30  # away from it: unblocked
hold controls::KEY_RIGHT, 45 # into it again: the second life
idle 20
