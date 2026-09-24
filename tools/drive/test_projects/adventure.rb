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
  press controls::KEY_I
  idle 20
  press controls::KEY_I
  idle 16
  press controls::KEY_I
  idle 10
  press controls::KEY_DOWN
  idle 10
  hold controls::KEY_DOWN, 16
  hold [controls::KEY_DOWN, controls::KEY_I], 2
  hold controls::KEY_DOWN, 30
  hold controls::KEY_UP, 30
  hold controls::KEY_LEFT, 45
  idle 13
  press controls::KEY_I
  idle 10
  press controls::KEY_E
  idle 10
  press controls::KEY_I
  idle 20
  press controls::KEY_I
  idle 10
  hold controls::KEY_E, 6
  hold [controls::KEY_E, controls::KEY_I], 2
  hold controls::KEY_E, 4
  idle 20
  press controls::KEY_E
  idle 18
  press controls::KEY_I
  idle 48
  press controls::KEY_E
  idle 18
  press controls::KEY_I
  idle 28
  press controls::KEY_I
  idle 10
  press controls::KEY_Q
  idle 10
  press controls::KEY_DOWN
  idle 10
  press controls::KEY_RETURN
  idle 10
  press controls::KEY_I
  idle 40
end

on controls.gamepad(0) do
  idle 30
  press controls::PAD_A
  idle 10
  hold controls::PAD_DPAD_DOWN, 60
  hold [controls::PAD_DPAD_DOWN, controls::PAD_DPAD_RIGHT], 80
  idle 5
  hold [controls::PAD_Y, controls::PAD_DPAD_LEFT], 30
  idle 20
  idle 13
  press controls::PAD_START
  idle 20
  press controls::PAD_START
  idle 16
  hold [controls::PAD_Y, controls::PAD_DPAD_RIGHT], 40
  idle 230
  press controls::PAD_START
  idle 18
  press controls::PAD_RIGHT_SHOULDER
  idle 48
  press controls::PAD_START
  idle 30
end
