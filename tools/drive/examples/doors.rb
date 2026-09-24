# Input script for examples/doors. Run it for its whole length:
#
#   ruby tools/drive_test_project.rb examples/doors/main.rb --texts --ticks 900
#
# Walks the hero from the town's start to the gate, into the garden, onto the
# first pad, onto the second, and back through the garden's gate to the town.
# Every hold is one axis, so each ends where the map puts the next turn.
#
# What the report should show:
#
#   - **scenes reading `build :town`, `move Hero to :town`, then `build
#     :garden`, `move Hero to :garden`, `free :town`**, for the gate. The garden
#     is built in the sweep the move lands in, and the town is freed in the same
#     sweep, because nobody is left in it;
#   - **two more `move Hero to :garden` and nothing built or freed between
#     them**, for the pads. A move into the room the hero stands in only places
#     it again;
#   - **`build :town`, `move Hero to :town`, `free :garden`** for the way back.
#     The town is built anew: a room is a recipe, and nothing it held survived
#     the trip;
#   - **"In the town" from tick 1 and "In the garden" from tick 289**, the line
#     the world draws from `room_of`. It changes as the move lands, under the
#     cover;
#   - **135 `faded` calls**: 15 for the reveal as the hero first arrives, the
#     cover being complete from the start, and 30 for each of the four moves
#     after it, a quarter of a second of cover and a quarter of reveal;
#   - **no audio.** A door touched plays nothing, since it was given no sound.
#
# Each move pauses the hero from the request until its reveal ends, so every
# hold that reaches a door is followed by an idle long enough for the cover and
# the reveal. A key still held once the reveal ends walks the hero on.

idle 20
hold controls::KEY_UP, 12 # off the start, onto the open row north of the trees
hold controls::KEY_RIGHT, 132
hold controls::KEY_UP, 115 # up the clear column to the gate
idle 60
hold controls::KEY_RIGHT, 72 # from the garden's gate_in, under the first pad
hold controls::KEY_UP, 95 # onto it
idle 60
hold controls::KEY_UP, 25 # from beside the second pad, onto it
idle 60
hold controls::KEY_DOWN, 72 # from beside the first pad, level with the gate
hold controls::KEY_LEFT, 100 # and through it
idle 60
