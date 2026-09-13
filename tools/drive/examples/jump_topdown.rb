# Input script for examples/jump_topdown.
#
# One hop standing still, a walk south into the fence, and a second hop against
# it while still holding south. Run it with `--ticks 170`.
#
# What the report should show:
#
#   - **`sprite` spanning y (its fifth argument) from −18.0 to 0**, and first and
#     last both at 0. The hop peaks at exactly `HOP_PEAK` — the fixed step lands a
#     tick on the half-second's midpoint — and the run starts and ends on the
#     ground. That span is the picture leaving the ground, and it is the only
#     argument in the report that moves with a hop;
#   - **`rect` and `circle` placed at the same point for the whole run**, (2, 16)
#     for the feet box. Both are drawn in the hero's own local space, so a hop that
#     moved the node rather than its picture would still leave them where they
#     are. What moving the node would change is the camera, below;
#   - **`circle` spanning its radius from 0.5 to 1.0**: the shadow at half size at
#     the top of the hop, where the height equals `SHADOW_HALF_AT`;
#   - **the last `tilemap` call at camera (72.0, 77.0)**, which is the acceptance
#     test for "a hop does not clear a fence". 77 is the camera on a hero stopped
#     against the fence. The second hop is pressed there with south still held for
#     forty more ticks, so a hop that carried the hero's feet over the fence would
#     have ended the run with the camera further south. A run stopped mid-hop at
#     `--ticks 25` shows the other half: the camera still at (72.0, 43.0), where it
#     was before the hero left the ground, and `text` ending on `"In the air"`;
#   - **`text` ending on `"On the ground"`**, two `tilemap` calls per frame (ground
#     and obstacles), one clip per frame for the world and one for the
#     presentation, and no audio.
#
# Nothing here needs a seed: the map is a file and the timestep is fixed.

idle 10
press controls::KEY_SPACE # a hop standing still
idle 40
hold controls::KEY_DOWN, 40 # into the fence
hold [controls::KEY_DOWN, controls::KEY_SPACE], 5 # hop against it, still pushing south
hold controls::KEY_DOWN, 40
idle 20
