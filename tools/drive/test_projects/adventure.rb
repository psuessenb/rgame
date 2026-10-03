# Input script for test_projects/adventure, where the engine's features meet in
# one game. Run it with a seed:
#
#   ruby tools/drive_test_project.rb test_projects/adventure/main.rb \
#     --seed 4242 --texts
#
# The keyboard holds Tab from tick 40, through the opening cutscene. The skip
# lands at 76, not 40: the first hero's input is suspended until its arrival
# reveal ends, and the gate refuses a press begun on the poll it resumed on.
# The joins stay closed until the cutscene ends, so both tracks start about 80
# ticks later than they would without it.
#
# The heroes reach only for what they face. The keyboard's hero taps right to
# face the chest, which it reaches walking up and left, and the pad's taps right to
# face the crate before pulling it. Without the taps, the chest stays shut and the
# pad's first pull takes hold of nothing.
#
# ## The course
#
# The horn leaves both heroes in the town square. From tick 1650 they walk to
# the east gate, the pad's 36 ticks behind on a path 48 px shorter, so both
# touch it on tick 2040 and one move builds the course for both. The course is
# first updated on tick 2057, and the rafts move from then, so every hop below
# is timed from that tick. A change that moves the touch moves them all.
#
# The pad's hero arrives 48 px east of the keyboard's, so it waits 36 ticks
# longer and holds right 36 fewer. From the first hop on, the two stand on one
# spot. Both hop the three trenches together and reach `first`. The keyboard's
# hero walks north and pushes the crate into the first chasm, then comes back.
# Both board the shuttle with a hop as it comes close. Halfway across, the pad's
# hero walks off its north edge and falls, and comes back at `first`, 48 px
# east of the flag. The keyboard's hero rides on, hops onto the far bank as the
# shuttle turns, and reaches `second`.
#
# The budget is 90 objects a second, over the default 60, because the pad joins
# after the warm-up. Spawning its hero, bag and Hud at tick 142 is counted,
# about 430 objects, and the garden sign's scene about 60 more. The worst
# second, about 1,300 objects, builds the course. The whole run allocates about
# 77 a second.
#
# What the report should show:
#
#   - **"Morning in the town" from tick 3, in the one clip of the whole
#     window**, and the split from tick 143, as the pad joins;
#   - **the rooms in order**: the town built, both heroes moved to the garden,
#     the town freed, then built again as they return, and the garden freed.
#     Then the course built, both heroes moved to it, and the town freed;
#   - **"Keep off the flower beds" from tick 1063**, in the pad's region only,
#     while the keyboard's region draws the town;
#   - **"Checkpoint: start" from tick 2059 and "Checkpoint: first" from 2360**,
#     in both regions, then **"Falls: 1" from 2674 in the pad's region only**
#     and **"Checkpoint: second" from 2858 in the keyboard's only**;
#   - **`scaled` 96 times more than there are frames**: the crate's fall and
#     the pad's hero's, 24 ticks each, in both views;
#   - **"NPC" in both regions on every tick from 2059**: the walker never left
#     the ring;
#   - **the garden's song only where `media/music/garden.ogg` exists**, fading
#     in over the town's music, and the town's back as the heroes return. The
#     course claims no song, so the town's stops a second time as they leave
#     for it.

allocation_budget objects_per_second: 90

on controls::KEYBOARD do
  idle 40
  hold controls::KEY_TAB, 40
  idle 42
  hold controls::KEY_UP, 40
  hold [controls::KEY_UP, controls::KEY_LEFT], 10
  hold [controls::KEY_UP, controls::KEY_LEFT, controls::KEY_F4], 2
  hold [controls::KEY_UP, controls::KEY_LEFT], 78
  idle 6
  press controls::KEY_RIGHT
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
  idle 73
  hold controls::KEY_UP, 54 # to the east gate
  hold controls::KEY_RIGHT, 343
  idle 40 # the course
  hold controls::KEY_RIGHT, 112
  hold [controls::KEY_RIGHT, controls::KEY_SPACE], 1
  hold controls::KEY_RIGHT, 47
  hold [controls::KEY_RIGHT, controls::KEY_SPACE], 1
  hold controls::KEY_RIGHT, 47
  hold [controls::KEY_RIGHT, controls::KEY_SPACE], 1
  hold controls::KEY_RIGHT, 86
  hold controls::KEY_UP, 57
  hold controls::KEY_RIGHT, 34
  hold controls::KEY_DOWN, 57
  idle 3
  hold [controls::KEY_RIGHT, controls::KEY_SPACE], 1
  hold controls::KEY_RIGHT, 29
  idle 190
  hold controls::KEY_RIGHT, 35
  hold [controls::KEY_RIGHT, controls::KEY_SPACE], 1
  hold controls::KEY_RIGHT, 29
  hold controls::KEY_RIGHT, 85
  idle 60
end

on controls.gamepad(0) do
  idle 142
  press controls::PAD_A
  idle 10
  hold controls::PAD_DPAD_DOWN, 60
  hold [controls::PAD_DPAD_DOWN, controls::PAD_DPAD_RIGHT], 80
  idle 3
  press controls::PAD_DPAD_RIGHT
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
  idle 111
  hold controls::PAD_DPAD_UP, 54 # to the east gate
  hold controls::PAD_DPAD_RIGHT, 307
  idle 76 # the course
  hold controls::PAD_DPAD_RIGHT, 76
  hold [controls::PAD_DPAD_RIGHT, controls::PAD_A], 1
  hold controls::PAD_DPAD_RIGHT, 47
  hold [controls::PAD_DPAD_RIGHT, controls::PAD_A], 1
  hold controls::PAD_DPAD_RIGHT, 47
  hold [controls::PAD_DPAD_RIGHT, controls::PAD_A], 1
  hold controls::PAD_DPAD_RIGHT, 123
  idle 119
  hold [controls::PAD_DPAD_RIGHT, controls::PAD_A], 1
  hold controls::PAD_DPAD_RIGHT, 29
  idle 90
  hold controls::PAD_DPAD_UP, 20
  idle 100
end
