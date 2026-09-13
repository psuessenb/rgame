# Input script for examples/quick_wheel.
#
# The keyboard, one stretch per rule of a wheel held open by Tab: point east and
# let go of both at once; point south and let go of the arrow a few ticks before
# Tab; point west and leave the arrow up for a third of a second before Tab; point
# south-west and press Enter while holding, then let go of Tab.
# `quick_wheel_pad.rb` is the same wheel on a shoulder button and a real stick.
#
# What the report should show — the **last `text` call**, the caption naming
# what was chosen. It is drawn by the last node in the scene, so its final line
# is the last text of every frame. A budget's last frame is drawn before its last
# tick, so a caption trails the release by two:
#
#     --ticks  23  →  last("Chosen: nothing yet", 12, 450)
#     --ticks  24  →  last("Chosen: Save", 12, 450)        Tab and the arrow up on tick 22
#     --ticks  59  →  last("Chosen: Save", 12, 450)
#     --ticks  60  →  last("Chosen: Trophies", 12, 450)    Tab up four ticks after the arrow
#     --ticks 130  →  last("Chosen: Trophies", 12, 450)    Tab up twenty ticks after: nothing
#     --ticks 155  →  last("Chosen: Trophies", 12, 450)    Enter while holding chose nothing
#     --ticks 156  →  last("Chosen: Sound", 12, 450)       Tab up
#
# **24 and 60 are the grace window** (`Pointing::GRACE`, 0.15 s). With
# `grace: 0.0` passed to the wheel, both say "nothing yet": even letting go of
# both keys on one tick finds the stick at rest, because the menu reads the stick
# before it reads the release. **130** is the window running out.
#
# Also, at 180 ticks:
#
#   - **84 `line` calls**, the pointer — one per frame the wheel is open: Tab is
#     held for 12, 16, 32 and 24 ticks. Nothing of the wheel is drawn while it is
#     closed: **672 `image`** is 8 × 84, and **989 `circle`** is 11 × 84 — backdrop
#     (radius 198.0), dead zone, tip and eight discs — plus 65 outlines on the
#     frames something is focused;
#   - **720 `rect`**, the four dots, every frame. They move a quarter as far per
#     tick while the wheel is open; the report cannot show that, and a probe
#     prepended to `Dot#on_update` counted 1.5 px per tick for the first dot
#     against 0.375 for exactly the 12 ticks of the first opening;
#   - no audio, no scenes, one clip per frame.
#
# Nothing here needs a seed.

idle 10

hold controls::KEY_TAB, 2                                        # tick 10: open
hold [controls::KEY_TAB, controls::KEY_RIGHT], 10                # point east: Save
idle 20                                                          # tick 22: both up at once

hold controls::KEY_TAB, 2
hold [controls::KEY_TAB, controls::KEY_DOWN], 10                 # south: Trophies
hold controls::KEY_TAB, 4                                        # the arrow up first
idle 20                                                          # tick 58: Tab up inside the window

hold controls::KEY_TAB, 2
hold [controls::KEY_TAB, controls::KEY_LEFT], 10                 # west: Music
hold controls::KEY_TAB, 20                                       # the arrow up for a third of a second
idle 20                                                          # tick 110: Tab up at rest

hold controls::KEY_TAB, 2
# South-west: Sound, with Enter pressed while it is held.
hold [controls::KEY_TAB, controls::KEY_DOWN, controls::KEY_LEFT], 10
hold [controls::KEY_TAB, controls::KEY_DOWN, controls::KEY_LEFT, controls::KEY_RETURN], 2
hold [controls::KEY_TAB, controls::KEY_DOWN, controls::KEY_LEFT], 10
idle 20 # tick 154: Tab up
