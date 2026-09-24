# Input script for examples/equipment, on a synthetic controller.
#
#   ruby tools/drive_test_project.rb examples/equipment/main.rb --gamepad \
#     --script tools/drive/examples/equipment_pad.rb --ticks 400 --texts
#
# The keyboard script's walk on the d-pad, A and the shoulder buttons, through
# the real device path: the right shoulder shows the bag and the left one Gear
# again. The report is the keyboard run's one tick later, since a pad press
# reaches the game a tick after a key does: "Cloak" 100 from 47, "Tunic" from
# 147 and "In the bag" from 168. At 400 "Worn" still reads 66, and "Nothing" 68
# and "In the bag" 142, because the run ends a tick sooner after each change.

on controls.gamepad(0) do
  idle 20
  press controls::PAD_DPAD_DOWN
  idle 10
  press controls::PAD_DPAD_RIGHT
  idle 10
  press controls::PAD_A
  idle 20
  press controls::PAD_RIGHT_SHOULDER
  idle 20
  press controls::PAD_DPAD_DOWN
  idle 20
  press controls::PAD_LEFT_SHOULDER
  idle 20
  press controls::PAD_DPAD_RIGHT
  idle 10
  press controls::PAD_A
  idle 20
  press controls::PAD_RIGHT_SHOULDER
  idle 20
  press controls::PAD_DPAD_RIGHT
  idle 20
  press controls::PAD_LEFT_SHOULDER
  idle 20
  press controls::PAD_DPAD_LEFT
  idle 10
  press controls::PAD_DPAD_LEFT
  idle 10
  press controls::PAD_A
  idle 20
  press controls::PAD_RIGHT_SHOULDER
  idle 30
end
