# Input script for examples/pits.
#
# A walk south into the chasm, a fall and a respawn. Then a hop across the first
# trench, and at the second a walk off the edge with a hop four ticks after the
# step off: coyote time carries it across. Then C turns coyote time off, and the
# same late hop at the third trench comes too late. Run it with `--ticks 650`.
#
# What the report should show:
#
#   - **`sprite` drawn 590 times in 650 ticks.** Each respawn blinks the hero
#     out for five spells of six ticks, and a blink hides the whole node, so
#     the 60 missing draws are the two flashes. The flash draws no `faded`:
#     a node at opacity 0 is not drawn at all. The sprite's y (its fifth
#     argument) spans −40.0 to −22, the hop's 18px above the standing −22;
#   - **`scaled` 698 times**: once a frame at (1.0, 1.0) for the presentation,
#     and 48 more, 24 for each of the two falls, from about 1 toward 0.0. That
#     is the hero shrinking into a pit;
#   - **translates reaching x 385.3 and y 348.0**: the hero stopped over the
#     chasm at y 348 and over the third trench at x 385.3, just past its edge at
#     384. The second trench's edge is at 288, and nothing stops the hero there;
#   - **`rect` spanning its width, the third argument, from 0.0 to 120**: the
#     coyote bar, full on the ground and empty in the air. It is drawn 1091
#     times, the empty bar every frame and the full one on the 441 frames before
#     C turns coyote time off;
#   - **`text` ending on `"Coyote time off"`**, three `tilemap` calls a frame
#     (ground, pits, obstacles) and no audio.
#
# Nothing here needs a seed: the map is a file and the timestep is fixed. The
# ticks were read off a traced run: the hero steps off the second trench on
# tick 389 and hops on 393, and steps off the third on tick 474.

idle 10
hold controls::KEY_DOWN, 140 # into the chasm; falls, and comes back flashing
idle 90
hold controls::KEY_RIGHT, 70
hold [controls::KEY_RIGHT, controls::KEY_SPACE], 1 # a hop across the first trench
hold controls::KEY_RIGHT, 82
hold [controls::KEY_RIGHT, controls::KEY_SPACE], 1 # four ticks off the edge: across
hold controls::KEY_RIGHT, 36
idle 10
press controls::KEY_C # coyote time off
hold controls::KEY_RIGHT, 36
hold [controls::KEY_RIGHT, controls::KEY_SPACE], 1 # four ticks off the edge: too late
hold controls::KEY_RIGHT, 23
idle 120
