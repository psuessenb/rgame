# Input script for examples/input_holds, on a synthetic controller.
#
#   ruby tools/drive_test_project.rb examples/input_holds/main.rb --gamepad \
#     --script tools/drive/examples/input_holds_pad.rb --ticks 240
#
# The same four gestures as the keyboard script, through the real device path: A
# held and then tapped, the left shoulder button alone, and both shoulder
# buttons together. The chord is the half of `swap`'s entry that names pad ids,
# which is what a chord per device is for.
#
# What the report should show, on the `audio` count and the last `text` call:
#
#     --ticks  56  →  0 × sound, last("Chest: shut")
#     --ticks  57  →  1 × sound                            the hold reaches 0.6 s
#     --ticks  58  →  1 × sound, last("Chest: searched…")
#     --ticks 112  →  2 × sound                            the release comes inside 0.3 s
#     --ticks 172  →  3 × sound                            the chord's second button arrives
#
# Each lands a tick or two later than in the keyboard script: a synthetic
# controller's buttons reach the game through SDL, and the harness feeds it one
# frame at a time.
#
# At 240 ticks the counts match the keyboard run's: 1200 `text`, 510 `rect` —
# 30 of them the shield, drawn while the shoulder button is held alone and not
# while the chord holds it.

on controls.gamepad(0) do
  idle 20
  hold controls::PAD_A, 60
  idle 20
  hold controls::PAD_A, 10
  idle 20
  hold controls::PAD_LEFT_SHOULDER, 30
  idle 10
  hold [controls::PAD_LEFT_SHOULDER, controls::PAD_RIGHT_SHOULDER], 30
  idle 40
end
