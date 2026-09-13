# Input script for examples/quick_wheel, on a synthetic controller.
#
#   ruby tools/drive_test_project.rb examples/quick_wheel/main.rb --gamepad \
#     --script tools/drive/examples/quick_wheel_pad.rb --ticks 121
#
# Only `--gamepad` plays this: the real device path for the left shoulder and the
# stick. The shoulder held, the stick pushed east, the stick let go three ticks
# before the shoulder; then the shoulder held with the stick pushed south and let
# go for half a second before the shoulder.
#
# What the report should show, on the last `text` call:
#
#     --ticks  39  →  last("Chosen: nothing yet", 12, 450)
#     --ticks  40  →  last("Chosen: Save", 12, 450)      the stick came home inside the grace window
#     --ticks 121  →  last("Chosen: Save", 12, 450)      at rest for longer: nothing
#
# A synthetic pad reaches the game a tick later than the keyboard backend, so the
# caption trails the shoulder's release (tick 37) by three. With `grace: 0.0` on
# the wheel, 57 still says "nothing yet". **17 `line` calls at 40 and 61 at 121**:
# the wheel draws only while the shoulder is held.

on controls.gamepad(0) do
  idle 20

  hold controls::PAD_LEFT_SHOULDER, 4
  hold controls::PAD_LEFT_SHOULDER, 10, axes: { controls::AXIS_LEFT_X => 1.0 }
  hold controls::PAD_LEFT_SHOULDER, 3
  idle 20

  hold controls::PAD_LEFT_SHOULDER, 4
  hold controls::PAD_LEFT_SHOULDER, 10, axes: { controls::AXIS_LEFT_Y => 1.0 }
  hold controls::PAD_LEFT_SHOULDER, 30
  idle 20
end
