on controls::KEYBOARD do
  idle 10
  hold controls::KEY_RIGHT, 100
  hold controls::KEY_DOWN, 80
  hold controls::KEY_RIGHT, 40
  idle 10
end

on controls.gamepad(0) do
  idle 20
  press controls::PAD_A
  idle 5
  hold controls::PAD_DPAD_LEFT, 40
  idle 5
  press controls::PAD_B
  idle 10
  press controls::PAD_DPAD_DOWN
  idle 10
  press controls::PAD_DPAD_DOWN
  idle 10
  hold controls::PAD_DPAD_LEFT, 40
  idle 60
end
