# Input script for examples/game_menu.
#
# Walks a little, opens the menu, moves the focus around, closes it with Escape,
# walks again, reopens it and activates Resume with Enter.
#
# It deliberately never activates **Quit**: that calls `close` on the game, the
# loop stops, and the run ends before its tick budget with a report that looks
# like a crash. If you want to check Quit works, drive it on its own.
#
# What the report should show:
#
#   - `nine_slice` calls appearing **only while the menu is open** — the panel
#     plus one per item, so four per frame across the two open stretches, and
#     none at all in between. That is `draw_children` hiding the subtree;
#   - **one clip per frame** covering the whole window: the PlayerLayer drawing
#     the single player's region. It is pushed every frame whether the menu is
#     open or not, because the layer is always there;
#   - `sprite` calls at a steady five per frame throughout — the hero and the
#     four villagers. The hero being paused stops it *moving*, not drawing;
#   - a translate count that keeps climbing while the menu is open, because the
#     villagers are still walking. That is the whole point of the example, and
#     it is the number to watch if pausing ever starts pausing too much.
#
# Run it with `--seed N` if you want two runs to be comparable: the villagers
# wander off a seeded RNG, and without a seed the example still fixes its own
# so a plain run is reproducible too.

idle 5
hold controls::KEY_RIGHT, 25
hold controls::KEY_DOWN, 20

press controls::KEY_ESCAPE # open
idle 8
press controls::KEY_DOWN   # Resume -> (Save game is disabled and skipped) -> Quit
idle 8
press controls::KEY_UP     # back to Resume
idle 8
press controls::KEY_ESCAPE # close without activating anything
idle 5

hold controls::KEY_LEFT, 25 # walking again proves the hero was only paused

press controls::KEY_ESCAPE # open again
idle 8
press controls::KEY_RETURN # activate Resume, which closes it
idle 20
