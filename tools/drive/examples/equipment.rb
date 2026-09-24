# Input script for examples/equipment.
#
#   ruby tools/drive_test_project.rb examples/equipment/main.rb --ticks 400 --texts
#
# The character starts in the straw hat and the boots, with nothing on the body.
# Step down to Body, cross right into the clothes and wear the Cloak, then look
# at it in the bag with E. Back on Gear with Q, step right to the Tunic and wear
# it in the Cloak's place, and look at the Tunic in the bag. Back on Gear, cross
# left to Body, take the Tunic off, and look at it in the bag once more.
#
# What the report should show: the **piece names and the bag panel's two words
# under `texts drawn`**. Taking a piece off draws "Nothing", which the Body slot
# has drawn since tick 0, so each change shows as a count or a first tick at a
# checkpoint. `--texts` keeps the tick a string first appeared, and a budget's
# last frame is drawn before its last tick runs, so a press on tick N shows at
# N + 1:
#
#     --ticks  46  →  "Nothing" 46, and no "Cloak"
#     --ticks  47  →  "Cloak" from 46, "Nothing" still 46       the Cloak is worn
#     --ticks  89  →  "Worn" 22 from 67                         the bag, on the Straw hat
#     --ticks 111  →  "Worn" 44, and no "In the bag"             the Cloak, in the bag and worn
#     --ticks 147  →  "Tunic" from 146                          the Tunic replaces it
#     --ticks 189  →  "In the bag" 22 from 167, "Cloak" 100     the Cloak, no longer worn
#     --ticks 211  →  "Worn" 66, "In the bag" still 22           the Tunic, worn
#     --ticks 259  →  "Nothing" 47                              the Tunic is off
#     --ticks 400  →  "Nothing" 67, "Worn" 66, "In the bag" 143, "Cloak" 100
#
# **"Cloak" stands at 100 from 189 on.** Nothing draws its name once the Tunic
# replaced it and the bag's focus left it, so the Body slot really changed.
# **"In the bag" from 279 on is the Tunic taken off**: focus in the bag stayed on
# it, and the word beside its name changed.
#
# Also, at 400: 400 ticks against 400 frames, no scene entered, one clip per
# frame, no audio, and 191 `sprite` calls, one per Gear frame. Nothing here is
# random, so no seed is needed.

idle 20
press controls::KEY_DOWN
idle 10
press controls::KEY_RIGHT
idle 10
press controls::KEY_RETURN
idle 20
press controls::KEY_E
idle 20
press controls::KEY_DOWN
idle 20
press controls::KEY_Q
idle 20
press controls::KEY_RIGHT
idle 10
press controls::KEY_RETURN
idle 20
press controls::KEY_E
idle 20
press controls::KEY_RIGHT
idle 20
press controls::KEY_Q
idle 20
press controls::KEY_LEFT
idle 10
press controls::KEY_LEFT
idle 10
press controls::KEY_RETURN
idle 20
press controls::KEY_E
idle 30
