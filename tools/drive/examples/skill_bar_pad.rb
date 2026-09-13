# Input script for examples/skill_bar, on a synthetic controller.
#
#   ruby tools/drive_test_project.rb examples/skill_bar/main.rb --gamepad \
#     --script tools/drive/examples/skill_bar_pad.rb --ticks 60
#
# The d-pad steps along the bar and A uses the focused tool, through the real
# device path: right three times to the Hammer and A, then left to the Torch and
# A. The hotkeys are number keys, so the keyboard script covers them.
#
# What the report should show, on the last `text` call and the `audio` count:
#
#     --ticks 28  →  1 × sound, last("Used: nothing yet")   A goes down on tick 28
#     --ticks 29  →  1 × sound, last("Used: Hammer")
#     --ticks 60  →  2 × sound, last("Used: Torch")

on controls.gamepad(0) do
  idle 20
  press controls::PAD_DPAD_RIGHT
  press controls::PAD_DPAD_RIGHT
  press controls::PAD_DPAD_RIGHT
  press controls::PAD_A
  idle 10
  press controls::PAD_DPAD_LEFT
  press controls::PAD_A
  idle 20
end
