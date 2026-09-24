allocation_budget objects_per_second: 90

on controls::KEYBOARD do
  idle 40
  hold controls::KEY_TAB, 40
  idle 42
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
  press controls::KEY_I
  idle 210
  press controls::KEY_I
  idle 10
  hold controls::KEY_UP, 27
  hold controls::KEY_RIGHT, 257
  idle 110
  press controls::KEY_I
  idle 21
  press controls::KEY_I
  idle 50
  press controls::KEY_I
  idle 30
end

on controls.gamepad(0) do
  idle 142
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
  idle 102
  hold controls::PAD_DPAD_RIGHT, 6
  hold controls::PAD_DPAD_UP, 164
  idle 50
  press controls::PAD_A
  idle 2
  hold controls::PAD_DPAD_RIGHT, 36
  hold controls::PAD_DPAD_UP, 92
  idle 186
  hold controls::PAD_DPAD_RIGHT, 27
  hold controls::PAD_DPAD_UP, 44
  idle 90
end
