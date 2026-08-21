# Two-player script for examples/15_tiled_world.
#
# The acceptance test for split-screen. Player one is on the keyboard from the
# start; the second seat is empty, so the game opens as an ordinary full-screen
# one-player session. Twenty ticks in, a controller presses confirm — a second
# walker appears and the screen splits — and from then on the two walk in
# different directions, so the two viewports carry visibly different cameras.
#
# Tracks are absolute and independent: both players act at the same time, not
# in turn.

on controls::KEYBOARD do
  idle 10
  hold controls::KEY_RIGHT, 70
  hold controls::KEY_UP, 60
  hold [controls::KEY_RIGHT, controls::KEY_UP], 40
  idle 20
end

on controls.gamepad(0) do
  idle 20
  press controls::PAD_A            # join: seats player two, splits the screen
  idle 5
  hold controls::PAD_DPAD_LEFT, 60 # the other way, so the cameras diverge
  hold controls::PAD_DPAD_DOWN, 60
  tilt controls::AXIS_LEFT_X, 0.6, 40
  idle 10
end
