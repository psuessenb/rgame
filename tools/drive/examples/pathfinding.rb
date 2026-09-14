# Input script for examples/pathfinding.
#
# Walks the cursor from the hero's tile, (24, 18) north-east of the fence, to
# (4, 33) south-west of it — twenty tiles west and fifteen south, well away from
# the gap at columns 12 to 14 — and confirms. Idles while the hero walks there
# (it arrives about 300 ticks after the confirm). Then walks the cursor onto the
# tree at (7, 31) and confirms again, which there is no route to.
#
# A held direction moves the cursor on the tick it goes down and every 8 ticks
# after (ActionTrigger's 0.12 s cooldown at 60 ticks a second), so a hold of
# `8n + 1` ticks moves it n + 1 tiles. The holds below are sized by that.
#
# What the report should show, at `--ticks 630`:
#
#   - **the last `text` reading `"no route there; arriv..."`**, which is the
#     acceptance test in one line. The status label is the last text drawn each
#     frame and leads with the newest fact: the tree was refused, and the route
#     before it had *arrived* — `on_finished` fired, which a walker held by a
#     tile corner it was routed past would never do. Untruncated, it reads
#     `no route there; arrived: 6 waypoints, 26 cells`;
#   - **`rect` from `(390, 294, 4, 4)` to `(70, 534, 4, 4)`**: the route's dots,
#     first the hero's own tile (24, 18) and last the target (4, 33), each at
#     `tile * 16 + 6`. Nothing else in the scene draws a rect;
#   - **11986 `rect` and 4825 `line` calls**, which is how the report shows the
#     two drawings side by side. The cursor draws 4 lines every frame (2520 over
#     630), leaving 2305; the route was on screen for 461 frames, and
#     11986 / 461 = 26 dots and 2305 / 461 = 5 lines a frame — 26 cells pulled
#     tight into 6 waypoints;
#   - **`line` spanning x up to 392.0 and y up to 536.0**: the walked route's
#     ends at the hero's feet. 392 is the start tile's centre, where the hero's
#     feet stand at the beginning (`24.5 * 16`); 536 is the target tile's centre
#     row (`33.5 * 16`), where they stand at the end. The zeros are the cursor's
#     outline, drawn in its own local space;
#   - **`sprite` spanning rows 0..2 and ending as it began**, on row 0 frame 0:
#     the hero faced the way it walked with nothing pressing a direction, and was
#     standing once it arrived;
#   - **`tilemap` camera from (0.0, 0.0) to (0.0, 160.0)**, 160 being the
#     southern clamp of a 640-tall map in a 480-tall window. The camera follows
#     the cursor, so this is the cursor going south, not the hero;
#   - **translates spanning x −72..384 and y −160..528**: the camera as its
#     opposite, the hero's start at x 384, and the cursor's southernmost tile at
#     y 528 (`33 * 16`);
#   - **no audio, no scenes.**
#
# Nothing here needs a seed: there is no RNG, the map is a file, and the timestep
# is fixed.

idle 10
hold [controls::KEY_DOWN, controls::KEY_LEFT], 113 # 15 tiles south-west
hold controls::KEY_LEFT, 40                        # 5 more west, to (4, 33)
idle 5
press controls::KEY_RETURN
idle 400 # the walk, and some standing
hold controls::KEY_RIGHT, 17 # 3 tiles east
hold controls::KEY_UP, 9     # 2 tiles north, onto the tree at (7, 31)
idle 5
press controls::KEY_RETURN
idle 20
