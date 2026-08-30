# Input script for examples/scroll_map.
#
# Starts at the middle of the map and pans to each edge in turn, holding long
# enough to reach every clamp: the map is 960x640 and the window 640x480, so the
# camera has only 320x160 pixels of travel and stops well before the rig does.
#
# What the report should show:
#
#   - one `tilemap` call per layer per frame — two layers, so twice the frames;
#   - a `line` pair per frame for the crosshair, and one screen-space `text`;
#   - **one clip per frame** covering the whole window: the WorldView drawing
#     the world for the single viewport.
#
# ## Reading the translate range
#
# It aggregates two different things, which is worth knowing before treating any
# number in it as a regression:
#
#   - the WorldView's camera translate, which is the *negative* camera offset;
#   - the rig's own node transform, which is its world position.
#
# So the range runs from the furthest camera offset to the furthest the rig got.
# The half that means something here is **the negative end, which must stop at
# exactly -320.0 and -160.0** — world minus view on each axis, which is where
# `Camera#resolve` clamps. A run that reads past either has a camera that is no
# longer bounded by the world, and the symptom in the window is the void past
# the map edge scrolling into view.
#
# The positive end is just the rig, and follows from the script: 220 px/s for 45
# ticks is 165 px, so holding right from the middle puts it at 480 + 165 = 645.
# It is allowed to reach the map edge while the camera has already stopped —
# that is what walking to the edge of a map looks like.

idle 5
hold controls::KEY_RIGHT, 45 # east, and well past where the camera stops
hold controls::KEY_DOWN, 40  # south-east corner
hold controls::KEY_LEFT, 80  # all the way west
hold controls::KEY_UP, 70    # north-west corner
hold [controls::KEY_RIGHT, controls::KEY_DOWN], 30 # diagonal, back toward the middle
idle 10
