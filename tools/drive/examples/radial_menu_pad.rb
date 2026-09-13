# Input script for examples/radial_menu, on a synthetic controller.
#
#   ruby tools/drive_test_project.rb examples/radial_menu/main.rb --gamepad \
#     --script tools/drive/examples/radial_menu_pad.rb --ticks 112
#
# Only `--gamepad` plays this: it runs the whole real path — SDL, the C input
# snapshot, ActionMapper's per-axis dead zone — which is what an analog
# deflection needs. The stick nudged a third of the way and A pressed; pushed
# fully east and A pressed; pointed south-west, let go, and A pressed at rest.
#
# What the report should show, again on the last `text` call:
#
#     --ticks  38  →  last("Chosen: nothing yet", 12, 450)   the nudge chose nothing
#     --ticks  60  →  last("Chosen: Yellow", 12, 450)
#     --ticks 112  →  last("Chosen: Yellow", 12, 450)        A at rest chose nothing
#
# At 38 the pointer's tip is at **35.3**, inside the dead-zone disc (radius 75).
# A raw 0.35 arrives as 0.235, not 0.35: ActionMapper's own per-axis dead zone
# (0.15) is taken off and the rest rescaled before the wheel sees it, so the
# wheel's 0.5 corresponds to a raw deflection of about 0.58 along an axis.
#
# The south-west point spans the tip to −106.1 on x and 106.1 on y: a raw ±0.8
# on both axes is longer than 1 after rescaling, and the pointer is clamped to
# the ring.

on controls.gamepad(0) do
  idle 20

  tilt controls::AXIS_LEFT_X, 0.35, 10
  hold controls::PAD_A, 2, axes: { controls::AXIS_LEFT_X => 0.35 }
  tilt controls::AXIS_LEFT_X, 0.35, 8

  tilt controls::AXIS_LEFT_X, 1.0, 10
  hold controls::PAD_A, 2, axes: { controls::AXIS_LEFT_X => 1.0 }
  tilt controls::AXIS_LEFT_X, 1.0, 8

  hold [], 20, axes: { controls::AXIS_LEFT_X => -0.8, controls::AXIS_LEFT_Y => 0.8 }
  idle 10
  press controls::PAD_A

  idle 20
end
