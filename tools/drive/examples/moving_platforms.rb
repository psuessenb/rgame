# Input script for examples/moving_platforms.
#
# A walk to the edge of the west bank, and a wait for the raft. A hop as it
# comes close lands on it, and it carries the hero east. A walk to its east edge
# and a hop as it turns land on the far bank. Then a hop back west, with the
# raft far off, falls into the chasm, and the hero comes back on the west bank.
# Run it with `--ticks 1020`.
#
# What the report should show:
#
#   - **`sprite` drawn 9150 times in 1020 ticks.** 8160 are the raft's eight
#     planks every frame, from `tiles.json` at row 6, columns 0, 1 and 3,
#     placed from −32 to 16 about its centre. The other 990 are the hero, less
#     the 30 frames the respawn's flash hides them;
#   - **`scaled` 1044 times**: once a frame at (1.0, 1.0) for the presentation,
#     and 24 more from about 1 toward 0.0, the one fall;
#   - **`tilemap`'s camera x spanning 0.0 to 305.3**, and translates reaching
#     x 625.3: the camera leaves the west bank riding the raft and follows the
#     hero onto the far bank, which stands at x 625.3. The respawn cuts it back;
#   - **three `tilemap` calls a frame** (ground, pits, obstacles), two `text`
#     lines, and no audio.
#
# Nothing here needs a seed: the map is a file and the timestep is fixed. The
# ticks were read off a traced run: the hero hops on tick 475 and lands on the
# raft on 493, hops off on 742 and lands on the far bank on 772, and hops back
# on 833 to land in the chasm on 863.

idle 10
hold controls::KEY_RIGHT, 36 # to the bank's edge
idle 428
hold [controls::KEY_RIGHT, controls::KEY_SPACE], 1 # onto the raft as it comes close
hold controls::KEY_RIGHT, 20
idle 205 # carried east
hold controls::KEY_RIGHT, 41 # to the raft's east edge
hold [controls::KEY_RIGHT, controls::KEY_SPACE], 1 # onto the far bank as the raft turns
hold controls::KEY_RIGHT, 30
idle 60
hold [controls::KEY_LEFT, controls::KEY_SPACE], 1 # back, with the raft far off: into the chasm
hold controls::KEY_LEFT, 30
idle 150
