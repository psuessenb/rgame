# Input script for examples/effects.
#
# Enter at tick 30, L at 122, Space at 184, and L and Space together at 256 and
# 258. The report adds up the whole run, so the checkpoints are the counts at
# `--ticks` 30, 122, 184, 256, 320 and 400, each under `--seed 4242`:
#
#   | ticks | rect   | line | blended | faded |
#   |-------|--------|------|---------|-------|
#   | 30    | 360    | 0    | 28      | 0     |
#   | 122   | 3124   | 0    | 120     | 70    |
#   | 184   | 5063   | 576  | 214     | 103   |
#   | 256   | 7929   | 576  | 333     | 103   |
#   | 320   | 10519  | 1152 | 476     | 136   |
#   | 400   | 13017  | 1152 | 556     | 136   |
#
# What each stretch shows:
#
#   - **`blended` once a frame from the torch**, all run long. Its first two
#     frames have no embers yet, so 30 ticks read 28. A stretch with a bolt or
#     sparkles on screen reads one more a frame for each, and the last 80 ticks
#     read the torch's 80 alone;
#   - **`faded` only while a fade, the flash or the bolt runs.** The cover and
#     the reveal add 70 before tick 122. A fade at full strength pushes no
#     `faded`, so the bolt adds some only while it fades out. None after 320;
#   - **`line` only while a bolt shows**: 18 a frame, a glow and a core for each
#     of its 9 segments, for 32 frames of each strike;
#   - **`rect` about 31 a frame with the torch alone**: the room's four, its
#     stick, and some 26 embers. It reads about 40 a frame while a burst of 16
#     sparkles lives, from 184 to 256.
#
# The example passes `seed:` to its game, so two runs at one budget match.
#
# Under `--allocations`, 6.4 objects a second, on 6 of 301 ticks, within the
# default budget. `particles_allocation_spec.rb` and `screen_fade_spec.rb` hold
# a burst, a stream, a fade and their drawing to nothing per frame.

idle 30
press controls::KEY_RETURN # cover, then reveal
idle 90
press controls::KEY_L      # a bolt, and the flash with it
idle 60
press controls::KEY_SPACE  # sparkles
idle 70
press controls::KEY_L
press controls::KEY_SPACE
idle 60
