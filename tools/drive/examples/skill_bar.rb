# Input script for examples/skill_bar.
#
#   ruby tools/drive_test_project.rb examples/skill_bar/main.rb --ticks 180
#
# Step right twice to the Torch and use it with Enter; use the Watering can with
# 5; press Enter again; hold 2 for twenty ticks; step left twice to the Wand and
# press 1 and Enter on the same tick. `skill_bar_pad.rb` steps with the d-pad
# and uses A.
#
# What the report should show: the **last `text` call**, the "Used" caption, and
# the **`audio` count**, one click per use. A budget's last frame is drawn before
# its last tick runs, so a use whose click is counted at N shows in the caption
# at N + 1:
#
#     --ticks  25  →  1 × sound, last("Used: nothing yet")   Enter goes down on tick 25
#     --ticks  26  →  1 × sound, last("Used: Torch")
#     --ticks  49  →  2 × sound, last("Used: Watering can")  5, with the Torch focused
#     --ticks  72  →  3 × sound, last("Used: Torch")         Enter: focus never left the Torch
#     --ticks 142  →  4 × sound, last("Used: Wrench")        2 held for 20 ticks uses it once
#     --ticks 180  →  5 × sound, last("Used: Wand")          1 and Enter together use it once
#
# The one at **72** is what a hotkey not moving focus looks like from outside:
# had 5 focused the Watering can, Enter would have used it again. The last two
# are the two ways a press does not add up — a held hotkey is one edge, and two
# sources on one button are one activation; either going wrong makes 180 read
# six or more clicks, or twenty-odd.
#
# Also, at 180 ticks:
#
#   - **eight `text` calls per frame**, 1440 — five captions under the tools, the
#     instructions, and the two status lines — and **five `image` calls**, 900;
#   - **1106 `circle` calls**: a disc per tool every frame (900; `first(50.0,
#     43.0, 43.0)` is the first outline, centred in the 86 pixels above an
#     18-pixel caption), an outline round the focused one every frame (180), and
#     one round each tool drawn pressed while not focused — 6 frames for the
#     tapped Watering can, 20 for the held Wrench;
#   - **one clip per frame**, the presentation's, and six translates: the bar and
#     its five slots, x 0..432, y 0..300.
#
# The report keeps positional arguments only, and a pressed look is a keyword
# colour, so "the Watering can drew pressed while unfocused for PRESS_FEEDBACK"
# was counted with a probe prepended to UI::IconButton#_draw: 6 frames, 0.1 s
# at 60 Hz. The 26 extra outlines above are the same count seen from outside.
#
# Nothing here needs a seed.

idle 20
press controls::KEY_RIGHT
press controls::KEY_RIGHT
press controls::KEY_RETURN
idle 20
press controls::KEY_5
idle 20
press controls::KEY_RETURN
idle 20
hold controls::KEY_2, 20
idle 20
press controls::KEY_LEFT
press controls::KEY_LEFT
idle 10
press [controls::KEY_1, controls::KEY_RETURN]
idle 30
