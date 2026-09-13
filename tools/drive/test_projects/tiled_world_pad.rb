on controls.gamepad(0) do
  idle 20

  hold controls::PAD_DPAD_RIGHT, 40
  hold controls::PAD_DPAD_DOWN, 40

  tilt controls::AXIS_LEFT_X, 0.05, 20
  tilt controls::AXIS_LEFT_X, 1.0, 40
  tilt controls::AXIS_LEFT_Y, -1.0, 40
  tilt controls::AXIS_LEFT_X, 0.5, 30

  idle 10
end
