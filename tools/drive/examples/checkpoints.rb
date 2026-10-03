# Input script for examples/checkpoints.
#
# A hop across the first trench and on past the first flag, into the second
# trench: a fall, and the hero comes back at the first flag rather than at the
# start. Then hops across the second and third trenches, past the second flag
# to the last, and a walk south into the chasm: a fall, and the hero comes back
# at the last flag.
#
# What the report should show:
#
#   - **the status line changing three times**: `"Comes back at: the start"`
#     from tick 0, `"the first flag"` from tick 121, `"the second flag"` from
#     284 and `"the last flag"` from 416, and never back. The fall into the
#     second trench, between 121 and 284, leaves it on the first flag;
#   - **`scaled` 723 times**: once a frame at (1.0, 1.0) for the presentation,
#     and 48 more running toward 0.0, 24 for each of the two falls;
#   - **`sprite` drawn 2640 times**: the three flags on each of 675 frames, and
#     the hero on 615, since each respawn's `Blink` hides it for 30. The sprite
#     rows, the second argument, span 0 to 7: the hero's 0 to 2, and the
#     flags' post on row 6 and banner on row 7;
#   - **translates reaching x 520.0 and y 348.0**: the last flag's x, which the
#     hero walks to and then south from, and the chasm the hero stops over;
#   - no scene pushed and no audio.
#
# Nothing here needs a seed: the map is a file and the timestep is fixed. The
# ticks were read off a traced run: the hero stops over the second trench on
# tick 161 and stands on the first flag, at x 248, from tick 190. It stops over
# the chasm on tick 560 and stands on the last flag from 584.

idle 10
hold controls::KEY_RIGHT, 70
hold [controls::KEY_RIGHT, controls::KEY_SPACE], 1 # across the first trench
hold controls::KEY_RIGHT, 80 # past the first flag, into the second trench
idle 60
hold controls::KEY_RIGHT, 26
hold [controls::KEY_RIGHT, controls::KEY_SPACE], 1 # across the second trench
hold controls::KEY_RIGHT, 66 # past the second flag
hold [controls::KEY_RIGHT, controls::KEY_SPACE], 1 # across the third trench
hold controls::KEY_RIGHT, 110 # to the last flag
hold controls::KEY_DOWN, 150 # into the chasm
idle 100
