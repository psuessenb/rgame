# Input script for examples/block_puzzle.
#
#   ruby tools/drive_test_project.rb examples/block_puzzle/main.rb --ticks 625 --texts
#
# Solves the room: six pushes right take the first block home, and the second
# block is pushed right twice, refused by the wall of trees, and pushed down
# three times onto its square. The hero walks a pixel a tick, so every hold is
# counted in pixels; the walk left ends flush against the room's west wall,
# which lines the hero up with column 13 whatever it overshoots by.
#
# What the report should show, on `--texts`:
#
#   - **"Blocks home: 0 of 2" until tick 197**, then "1 of 2". Each push waits
#     PUSH_AFTER, 12 ticks, of pressing, and the hero walks 16 pixels after each
#     one to catch up with the block, so six pushes take most of the first hold.
#   - **"Solved!" from tick 597**, for the last 28 frames. Only a block pushed
#     down from column 17 lands on its square, so the refusal at column 18 is in
#     this line too: a block that had gone into the trees would never get home.
#   - **no audio**, two clips per frame — the window's and the WorldView's —
#     the tilemap's two layers drawn once each per frame, and 625 layers in the
#     `:overlay` band, one per frame for the help line and the count.
#
# The last hold down stops after 85 ticks, before a fourth push would take the
# block past its square.

idle 5
hold controls::KEY_RIGHT, 193   # six pushes: the first block is home at 197
hold controls::KEY_LEFT, 140    # back along row 12, flush against the west wall
hold controls::KEY_DOWN, 48     # to row 15, beside the second block
hold controls::KEY_RIGHT, 100   # two pushes, then refused by the trees at column 18
hold controls::KEY_UP, 20       # clear of the block's top edge
hold controls::KEY_RIGHT, 14    # over column 17
hold controls::KEY_DOWN, 85     # three pushes onto the square
idle 20
