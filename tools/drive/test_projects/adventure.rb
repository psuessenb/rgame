on controls::KEYBOARD do
  idle 10
  hold controls::KEY_UP, 40
  hold [controls::KEY_UP, controls::KEY_LEFT], 10
  hold [controls::KEY_UP, controls::KEY_LEFT, controls::KEY_F4], 2
  hold [controls::KEY_UP, controls::KEY_LEFT], 78
  idle 8
  press controls::KEY_E
  idle 20
  hold controls::KEY_E, 50
  idle 20
end

on controls.gamepad(0) do
  idle 30
  press controls::PAD_A
  idle 10
  hold controls::PAD_DPAD_DOWN, 60
  hold [controls::PAD_DPAD_DOWN, controls::PAD_DPAD_RIGHT], 80
  idle 20
end
