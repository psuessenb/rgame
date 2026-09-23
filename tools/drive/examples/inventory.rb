# Input script for examples/inventory.
#
#   ruby tools/drive_test_project.rb examples/inventory/main.rb --ticks 400 --texts
#
# Walk right along the bag's first row to the Hammer, and right once more into
# the verbs. Use it, step down to Drop and drop it. Come back left into the bag,
# step down three rows, the last of them past the window, and switch to the key
# items with E. Step right there, switch back with Q, and press up.
#
# What the report should show: the **item names under `texts drawn`**, each
# drawn only by a page's panel, the **`image` and `triangle` counts**, and the
# **`audio` count**, one click per verb. `--texts` keeps the tick a string first
# appeared, and a budget's last frame is drawn before its last tick runs, so a
# press on tick N shows at N + 1:
#
#     --ticks  45  →  0 × sound, Wand 20, Wrench 12 from 21, Torch 12 from 33
#     --ticks  94  →  2 × sound, Hammer 49, "Used: Hammer" 24 from 70
#     --ticks 115  →  "Dropped: Hammer" from 94, 1380 × image, 115 × triangle
#     --ticks 161  →  "Copper can" from 149, 1932 × image, 161 × triangle
#     --ticks 162  →  "Birch wand" from 161, 1944 × image, 163 × triangle
#     --ticks 184  →  "House key" from 183, 2200 × image, 205 × triangle
#     --ticks 227  →  "Cellar key" 22 from 205, 2372 × image, 205 × triangle
#     --ticks 228  →  "Birch wand" 23, 2384 × image, 207 × triangle
#     --ticks 400  →  2 × sound, "House key" 22, "Cellar key" 22, 4448 × image, 551 × triangle
#
# **Every bag frame draws 12 images**, the three rows in view, though the bag
# holds twenty items and then nineteen; the key items' page draws 4. So 4448 at
# 400 is 356 bag frames × 12 and 44 key-item frames × 4.
#
# **The triangles are the scroll.** The mark below the bag is drawn every bag
# frame. Until 161 there is one a frame. From the third step down, onto the
# Birch wand in the fourth row, the bag has scrolled and the mark above is drawn
# too, so 162 counts 163.
#
# **E shows the key items and Q the bag again.** From 184 each frame adds 4
# images and no mark. The key items' names count from 183 and stand still from
# the Q on 226. At 228 a frame adds 12 images and two marks: the bag came back
# scrolled, on the Birch wand it left. Up on 248 then moves to the Copper can,
# still in view, and scrolls nothing.
#
# **"Used: Hammer" is the crossing.** Had the row wrapped instead, Enter on tick
# 68 would have confirmed the Wand in the bag, which does nothing, and 70 would
# read no click. **"Watering can" from 115** is the crossing back landing on the
# button nearest Drop.
#
# Also, at 400: 400 ticks against 400 frames, no scene entered, one clip per
# frame. Nothing here is random, so no seed is needed.

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
press controls::KEY_DOWN
idle 10
press controls::KEY_DOWN
idle 10
press controls::KEY_DOWN
idle 20
press controls::KEY_E
idle 20
press controls::KEY_RIGHT
idle 20
press controls::KEY_Q
idle 20
press controls::KEY_UP
idle 30
