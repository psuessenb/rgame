on controls::KEYBOARD do
  idle 10
  hold controls::KEY_RIGHT, 60
  idle 5
  press controls::KEY_TAB
  idle 60
  press controls::KEY_TAB
  hold controls::KEY_UP, 50
  idle 20
end

on controls.gamepad(0) do
  idle 20
  press controls::PAD_A
  idle 5
  hold controls::PAD_DPAD_LEFT, 45
  idle 130
end
