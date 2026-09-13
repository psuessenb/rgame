on controls::KEYBOARD do
  idle 10
  hold controls::KEY_RIGHT, 70
  hold controls::KEY_UP, 60
  hold [controls::KEY_RIGHT, controls::KEY_UP], 40
  idle 20
end

on controls.gamepad(0) do
  idle 20
  press controls::PAD_A
  idle 5
  hold controls::PAD_DPAD_LEFT, 60
  hold controls::PAD_DPAD_DOWN, 60
  tilt controls::AXIS_LEFT_X, 0.6, 40
  idle 10
end
