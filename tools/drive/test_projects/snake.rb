# Input script for test_projects/snake.
#
# The snake reads `move_x`/`move_y` as *axes* and turns the moment one is
# non-zero, so steering is a held direction rather than a press. It starts
# already moving down from cell (10, 10) on a 20x20 grid, and a step takes
# MOVE_SPEED = 0.1s — six ticks at the fixed timestep — so each 36-tick hold
# below is six cells.
#
# The route is a rectangle walked twice, kept well inside the walls. Two things
# make that the right shape rather than an arbitrary one:
#
#   - **Nothing guards against a 180° turn.** Reversing into the body is
#     instant death, so every turn here is 90°.
#   - **Each side is longer than the body** (START_LENGTH = 6), so closing the
#     loop cannot run the head into the tail.
#
# The script is 312 ticks long, and the snake survives all of them. Past the end
# of a track everything rests, but the last direction *sticks* — nothing here
# re-centres it — so a longer budget walks it into the bottom wall and it dies
# every time, at around tick 350. Drive it with `--ticks 312` or less.
#
# What the report should show: `rect` and `line` calls, no scene transition, and
# a **translate range that widens with the tick budget** — that is the signal
# the snake is still moving. Do not read the draw counts for this: `Root#lose`
# pauses the grid, and a paused node still draws (Node2D gates `control` and
# `update` on `paused`, not `draw`), so a dead snake keeps its steady seven
# rects a tick and looks exactly like a live one.
#
# Draw counts are not comparable between runs either: the fruit is placed from
# an unseeded `Random.new`, so how fast the body grows varies. `--seed` does not
# help — snake does not read `RGAME_SEED`. Assert on structure, as always.

idle 24 # four cells down from the start, to (10, 14)

2.times do
  hold controls::KEY_RIGHT, 36 # -> col 16
  hold controls::KEY_UP,    36 # -> row 8
  hold controls::KEY_LEFT,  36 # -> col 10
  hold controls::KEY_DOWN,  36 # -> row 14, back where the loop began
end
