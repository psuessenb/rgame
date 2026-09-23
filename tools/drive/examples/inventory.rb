# Input script for examples/inventory.
#
#   ruby tools/drive_test_project.rb examples/inventory/main.rb --ticks 300 --texts
#
# Walk right along the bag's first row to the Hammer, and right once more into
# the verbs. Use it, step down to Drop and drop it. Come back left into the bag,
# then press up, which wraps inside the bag's column because no menu lies above.
#
# What the report should show: the **item names under `texts drawn`**, each
# drawn only by the panel under the bag, and the **`audio` count**, one click per
# verb. `--texts` keeps the tick a string first appeared, and a budget's last
# frame is drawn before its last tick runs, so a press on tick N shows at N + 1:
#
#     --ticks  45  →  0 × sound, Wand 20, Wrench 12 from 21, Torch 12 from 33
#     --ticks  70  →  1 × sound, Hammer 25 from 45, "Used: Hammer" not yet drawn
#     --ticks  94  →  2 × sound, Hammer 49, "Used: Hammer" 24 from 70
#     --ticks 115  →  2 × sound, Hammer 49, "Nothing chosen" 22, "Dropped: Hammer" from 94
#     --ticks 137  →  2 × sound, "Watering can" 22 from 115
#     --ticks 300  →  2 × sound, Hammer 49, "Gear" 163 from 137
#
# **"Used: Hammer" is the crossing.** Right at the end of the row on tick 56
# drew nothing new, because the panel keeps the item the bag last focused. Had
# the row wrapped instead, Enter on tick 68 would have confirmed the Wand in the
# bag, which does nothing, and 70 would read no click.
#
# **Hammer stays at 49 from 94 on**: the drop took it out of the bag, and nothing
# draws its name again. "Nothing chosen" is its first frame plus the 21 frames
# between the drop and the crossing back.
#
# **"Watering can" from 115** is the crossing back landing on the button nearest
# Drop. The drop moved the Watering can up into the first row's last slot.
# **"Gear" from 137** is up wrapping: the group has no menu above the bag, so the
# step wraps to the column's last row, which is short and answers with its last
# button.
#
# Also, at 300 ticks: 300 ticks against 300 frames, no scene entered, one clip
# per frame, and translates spanning x 0..400, y 0..70. Nothing here is random,
# so no seed is needed.

idle 20
press controls::KEY_RIGHT
idle 10
press controls::KEY_RIGHT
idle 10
press controls::KEY_RIGHT
idle 10
press controls::KEY_RIGHT
idle 10
press controls::KEY_RETURN
idle 10
press controls::KEY_DOWN
idle 10
press controls::KEY_RETURN
idle 20
press controls::KEY_LEFT
idle 20
press controls::KEY_UP
idle 30
