# Input script for test_projects/topdownplatformer, two devices at once.
#
# The pad joins on tick 10 and its hero stands beside the keyboard's, on the
# primary hero's respawn point. Both walk east, hop the three trenches together
# and reach `first`. The keyboard's hero walks north and pushes the crate into
# the first chasm, then comes back. Both board the shuttle with a hop each as it
# comes close. Halfway across, the pad's hero walks off its north edge and falls,
# and comes back at `first`, while the keyboard's hero rides on and hops onto the
# far bank as the shuttle turns. It reaches `second`, waits at the next chasm for
# the ring's west leg, rides the ring round its north side, hops off onto the
# far bank, and reaches `last`. Run it with `--seed 1 --texts --ticks 1654`.
#
# What the report should show:
#
#   1. **one clip of the whole window for 11 ticks, then two rows of 640x240**:
#      the texts per clip list `[0, 0, 640, 480]` 11 times, then `[0, 0, 640,
#      240]` for the keyboard and `[0, 240, 640, 240]` for the pad from tick 11;
#   2. **`Checkpoint: first` in both rows from tick 303**;
#   3. **the crate's fall before either hero's**: `scaled` 1750 times, once a
#      frame at (1.0, 1.0) for the presentation and 96 more running toward 0.0.
#      That is the crate's fall from tick 414 and the pad hero's from tick 617,
#      24 ticks each in both views. `rect` shows 3273 times, 24 fewer than two
#      views of every frame, as the crate's flash hides it on its way back;
#   4. **the cameras travelling east**: `tilemap`'s camera x spans 0.0 to 960.0,
#      the map's whole width, and each row's clip holds thousands of distinct
#      translates;
#   5. **`Falls: 1` in the pad's row only, from tick 617**, while the keyboard's
#      row keeps `Falls: 0`;
#   6. **`Checkpoint: second` from tick 798 and `Checkpoint: last` from tick
#      1618, in the keyboard's row only**;
#   7. **`NPC` drawn 3297 times**: once in the whole window for 11 ticks, then
#      once in each row on all 1643 ticks after. The walker never left the ring.
#
# The ticks were read off a traced run. The heroes hop on ticks 143, 191 and
# 239. The keyboard's hero pushes the crate over the edge on tick 414, and it
# comes back on 438. The heroes hop for the shuttle on ticks 477 and 482 and
# land aboard on 507 and 512. The pad's hero steps off on 611 and is back at
# `first` on 641. The keyboard's hero hops off the shuttle on 732 and lands on
# 762, hops for the ring on 982 and lands aboard on 1012, and hops off it on
# 1462, landing on 1492. The walker wanders by the course's seeded RNG, and
# runs with seeds 1 to 5 reach `last` on the same tick.

on controls::KEYBOARD do
  idle 30
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
  idle 135
  hold [controls::KEY_RIGHT, controls::KEY_SPACE], 1
  hold controls::KEY_RIGHT, 29
  idle 400
  hold controls::KEY_RIGHT, 50
  hold [controls::KEY_RIGHT, controls::KEY_SPACE], 1
  hold controls::KEY_RIGHT, 29
  hold controls::KEY_DOWN, 45
  hold controls::KEY_RIGHT, 88
  idle 30
end

on controls.gamepad(0) do
  idle 10
  press controls::PAD_A
  idle 18
  hold controls::PAD_DPAD_RIGHT, 112
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
