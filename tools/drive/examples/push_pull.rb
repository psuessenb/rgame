# Input script for examples/push_pull.
#
#   ruby tools/drive_test_project.rb examples/push_pull/main.rb --ticks 180 --texts
#
# Walks right into the upper-left crate and pushes it, then holds Left Shift and
# walks back, pulling it, then lets go and walks on alone.
#
# What the report should show, on `--texts`:
#
#   - **"Holding a crate" from tick 86, for 40 frames**, and "Hands free" for
#     the other 140. Shift is held from tick 85 to 125, and the line is drawn a
#     tick after it goes down. The count is the hold exactly, 40, which is the
#     rule that letting go lets go the same tick.
#   - **no audio**, and one clip per frame.
#
# The push itself shows only in the translates, and running the example is the
# way to see it; the specs under spec/rgame/engine/components/ pin the numbers.

idle 5
hold controls::KEY_RIGHT, 80                          # into the crate at (200, 150), and on
hold [controls::KEY_LEFT, controls::KEY_LSHIFT], 40   # pulling it back
hold controls::KEY_LEFT, 20                           # let go: the crate stays
idle 35
