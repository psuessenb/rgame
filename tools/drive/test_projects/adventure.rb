# Input script for test_projects/adventure, where the engine's features meet in
# one game. Run it with a seed and enough ticks for both tracks:
#
#   ruby tools/drive_test_project.rb test_projects/adventure/main.rb \
#     --seed 4242 --texts --ticks 1640
#
# The keyboard holds Tab from tick 40, through the opening cutscene. The skip
# lands at 76, not 40: the first hero's input is suspended until its arrival
# reveal ends, and the gate refuses a press begun on the poll it resumed on.
# The joins stay closed until the cutscene ends, so both tracks start about 80
# ticks later than they would without it.
#
# The budget is 90 objects a second, over the default 80, because the pad joins
# after the warm-up. Spawning its hero and bag at tick 142 is counted, about 315
# objects, and the garden sign's scene about 60 more.
#
# What the report should show:
#
#   - **"Morning in the town" from tick 3, in the one clip of the whole
#     window**, and the split from tick 143, as the pad joins;
#   - **the rooms in order**: the town built, both heroes moved to the garden,
#     the town freed, then built again as they return, and the garden freed;
#   - **"Keep off the flower beds" from tick 1063**, in the pad's region only,
#     while the keyboard's region draws the town;
#   - **the garden's song only where `media/music/garden.ogg` exists**, fading
#     in over the town's music, and the town's back as the heroes return.

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
