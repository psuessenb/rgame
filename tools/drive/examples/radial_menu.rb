# Input script for examples/radial_menu.
#
# The keyboard, pointing with the arrow keys: choose Save, point at Sound and let
# go without choosing it, press Enter with nothing held, try to choose Locked, and
# choose Trophies. `radial_menu_pad.rb` is the same wheel on a real stick.
#
# What the report should show — the **last `text` call**, which is the caption
# naming what was chosen. It is drawn by the last node in the scene, so its final
# line is the last text of every frame. Run the script at five budgets:
#
#     --ticks  35  →  last("Chosen: Save", 12, 450)       east and Enter
#     --ticks  65  →  last("Chosen: Save", 12, 450)       pointing at Sound, nothing pressed
#     --ticks 100  →  last("Chosen: Save", 12, 450)       Enter at rest chose nothing
#     --ticks 130  →  last("Chosen: Save", 12, 450)       Locked refused
#     --ticks 180  →  last("Chosen: Trophies", 12, 450)
#
# The one at **100** is the acceptance test. The last thing the arrows pointed at
# before letting go was Sound, so a wheel that kept its selection when the stick
# came home would say Sound there — and does, with the reset below the dead zone
# removed.
#
# Also:
#
#   - **two `text` calls per frame**, the captions, and **eight `image` calls** —
#     an icon per button, whether it is focused or not — **nine once something
#     is chosen**, the ninth being the chosen icon drawn last. No `nine_slice`:
#     the buttons are IconButtons on a disc style. At 600 ticks that is 5377
#     images, 577 frames of them showing the chosen icon;
#   - **eleven `circle` calls per frame** — the backdrop (radius 198.0: the
#     ring's bounds and 16 of padding), the dead zone, the pointer's tip, and a
#     disc per button — and a twelfth, the focused button's outline, on every
#     frame something is focused: 60 of the 600, so 6660 in all. **One `line`**,
#     the pointer. The tip and the line's end span −106.1..150.0; 106.1 is a
#     diagonal clamped to the ring: two arrow keys read as (1, 1), which is
#     longer than a stick can reach;
#   - **one clip per frame**, the presentation's. There is no WorldView and no
#     PlayerLayer; everything is screen space.
#
# Nothing here needs a seed.

idle 10
hold controls::KEY_RIGHT, 10                                   # point east: Save
hold [controls::KEY_RIGHT, controls::KEY_RETURN], 2            # chosen
hold controls::KEY_RIGHT, 8
idle 10

hold [controls::KEY_DOWN, controls::KEY_LEFT], 20              # point south-west at Sound, choose nothing
idle 10                                                        # let go
press controls::KEY_RETURN                                     # centred: must not choose Sound
idle 20

hold [controls::KEY_UP, controls::KEY_LEFT], 10                # north-west: Locked
hold [controls::KEY_UP, controls::KEY_LEFT, controls::KEY_RETURN], 2
hold [controls::KEY_UP, controls::KEY_LEFT], 8                 # refused
idle 20

hold controls::KEY_DOWN, 10                                    # south: Trophies
hold [controls::KEY_DOWN, controls::KEY_RETURN], 2
hold controls::KEY_DOWN, 8
idle 20
