# Input script for examples/input_holds.
#
#   ruby tools/drive_test_project.rb examples/input_holds/main.rb --ticks 240
#
# One button, held long and then tapped, and a chord over a button that already
# has a plain action: E for a second, E for a sixth of one, L for half a second,
# then L and R together. `input_holds_pad.rb` plays the same four gestures on a
# controller.
#
# What the report should show: the **last `text` call**, which is the chest's
# line, and the **`audio` count**, one click per event. A budget's last frame is
# drawn before its last tick runs, so an event counted at N shows in the caption
# at N + 1:
#
#     --ticks  55  →  0 × sound, last("Chest: shut")       nothing has passed a threshold
#     --ticks  56  →  1 × sound                            the hold reaches 0.6 s
#     --ticks  57  →  1 × sound, last("Chest: searched…")
#     --ticks 110  →  1 × sound                            E is down again, and nothing fired
#     --ticks 111  →  2 × sound                            the release comes inside 0.3 s
#     --ticks 112  →  2 × sound, last("Chest: open")
#     --ticks 171  →  3 × sound                            the chord's second button arrives
#
# The one at **110** is the rule that makes a button safe to declare twice: the
# first press was held for a second, so its release pressed nothing at all. Had
# the tap fired on the way out of the search, the count would read 2 by tick 81
# and the chest would say "open" after being searched.
#
# At 240 ticks:
#
#   - **five `text` calls per frame**, 1200 — two help lines and three status
#     lines;
#   - **510 `rect` calls**: the chest and its meter every frame (480), and the
#     shield for the **30** frames L is held alone. The chord holds L for 30
#     frames more and the shield does not draw, because a chord silences the
#     plain actions on its buttons. Were it not silenced the count would be 540;
#   - the meter's width is the third argument of the last `rect`, and it spans
#     0.0..96 — the hold counted from nothing to its full 0.6 s;
#   - **one clip per frame**, the presentation's, and three translates: the
#     chest, the shield and the caption.
#
# `--texts` lists the nine strings the example can draw and the tick each began
# on: 56 for the search, 111 for the tap, 171 for the swap, and 131 for the 30
# frames of "Blocking".
#
# Nothing here needs a seed.

idle 20
hold controls::KEY_E, 60    # a second: the hold fires, and the release is too late to tap
idle 20
hold controls::KEY_E, 10    # a sixth of a second: the release taps
idle 20
hold controls::KEY_L, 30    # the plain action on the chord's first button
idle 10
hold [controls::KEY_L, controls::KEY_R], 30 # the chord, which silences it
idle 40
