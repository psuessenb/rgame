# Input script for examples/radial_menu.
#
# The keyboard, pointing with the arrow keys: choose Yellow, point at Blue and let
# go without choosing it, press Enter with nothing held, try to choose Locked, and
# choose Teal. `radial_menu_pad.rb` is the same wheel on a real stick.
#
# What the report should show — the **last `text` call**, which is the caption
# naming what was chosen. It is drawn by the last node in the scene, so its final
# line is the last text of every frame. Run the script at five budgets:
#
#     --ticks  35  →  last("Chosen: Yellow", 12, 450)   east and Enter
#     --ticks  65  →  last("Chosen: Yellow", 12, 450)   pointing at Blue, nothing pressed
#     --ticks 100  →  last("Chosen: Yellow", 12, 450)   Enter at rest chose nothing
#     --ticks 130  →  last("Chosen: Yellow", 12, 450)   Locked refused
#     --ticks 180  →  last("Chosen: Teal", 12, 450)
#
# The one at **100** is the acceptance test. The last thing the arrows pointed at
# before letting go was Blue, so a wheel that kept its selection when the stick
# came home would say Blue there — and does, with the reset below the dead zone
# removed.
#
# Also:
#
#   - **ten `text` and eight `nine_slice` calls per frame**: a label and a panel
#     per item, whether it is focused or not, plus two captions;
#   - **four `circle` calls and one `line` per frame** — backdrop, dead zone,
#     swatch, and the pointer's tip — with the tip and the line's end spanning
#     −106.1..150.0. 106.1 is a diagonal clamped to the ring: two arrow keys read
#     as (1, 1), which is longer than a stick can reach;
#   - **one clip per frame**, the presentation's. There is no WorldView and no
#     PlayerLayer; everything is screen space.
#
# Nothing here needs a seed.

idle 10
hold controls::KEY_RIGHT, 10                                   # point east: Yellow
hold [controls::KEY_RIGHT, controls::KEY_RETURN], 2            # chosen
hold controls::KEY_RIGHT, 8
idle 10

hold [controls::KEY_DOWN, controls::KEY_LEFT], 20              # point south-west at Blue, choose nothing
idle 10                                                        # let go
press controls::KEY_RETURN                                     # centred: must not choose Blue
idle 20

hold [controls::KEY_UP, controls::KEY_LEFT], 10                # north-west: Locked
hold [controls::KEY_UP, controls::KEY_LEFT, controls::KEY_RETURN], 2
hold [controls::KEY_UP, controls::KEY_LEFT], 8                 # refused
idle 20

hold controls::KEY_DOWN, 10                                    # south: Teal
hold [controls::KEY_DOWN, controls::KEY_RETURN], 2
hold controls::KEY_DOWN, 8
idle 20
