# Input script for examples/inventory, on a synthetic controller.
#
#   ruby tools/drive_test_project.rb examples/inventory/main.rb --gamepad \
#     --script tools/drive/examples/inventory_pad.rb --ticks 400 --texts
#
# The keyboard script's walk on the d-pad, A and the shoulder buttons, through
# the real device path: the right shoulder shows the key items and the left one
# the bag again. The report is the keyboard run's one tick later, since a pad
# press reaches the game a tick after a key does: "House key" 22 from 184,
# "Cellar key" 22 from 206, and at 400 still 2 × sound, 4448 × image, 400 ticks
# against 400 frames. The triangles read 550, one fewer, because the run ends a
# tick sooner after the scroll.

on controls.gamepad(0) do
  idle 20
  press controls::PAD_DPAD_RIGHT
  idle 10
  press controls::PAD_DPAD_RIGHT
  idle 10
  press controls::PAD_DPAD_RIGHT
  idle 10
  press controls::PAD_DPAD_RIGHT
  idle 10
  press controls::PAD_A
  idle 10
  press controls::PAD_DPAD_DOWN
  idle 10
  press controls::PAD_A
  idle 20
  press controls::PAD_DPAD_LEFT
  idle 20
  press controls::PAD_DPAD_DOWN
  idle 10
  press controls::PAD_DPAD_DOWN
  idle 10
  press controls::PAD_DPAD_DOWN
  idle 20
  press controls::PAD_RIGHT_SHOULDER
  idle 20
  press controls::PAD_DPAD_RIGHT
  idle 20
  press controls::PAD_LEFT_SHOULDER
  idle 20
  press controls::PAD_DPAD_UP
  idle 30
end
