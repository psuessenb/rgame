# Input script for examples/collision.
#
# Walks the pale circle into the bottom-left crate, out of it, and in again —
# twice quickly, then once more a long time later — so the counter above that
# crate can be read as arrivals rather than as frames of overlap.
#
# That counter is the whole reason this script exists. `on_hit` fires once per
# pair, on the step the two start overlapping, and a count is the one thing a
# per-step signal could not produce: the number would be frames of contact, and
# it would climb while nothing happened. So a wrong number here is the edge
# having stopped being an edge, which no draw count would show.
#
# What the report should show:
#
#   - **the last `text` reading `visits: 4`**, at exactly this tick budget. That
#     is the bottom-left crate, drawn last of the four. Three of the four are the
#     times this script brings the walking circle to it from somewhere else; the
#     fourth is the drifting circle that falls through the same crate around tick
#     110. The edges are per *pair*, so the drifter announces itself whether or
#     not the walker is standing there at the time;
#   - **twenty-one `rect` calls per frame, flat** — the backdrop, nine vertical
#     and seven horizontal cell lines, and one per crate. Contacts change what a
#     crate is *coloured*, never how much is drawn, so a step in this count would
#     mean a node had stopped being reached;
#   - **seven `text`, four `circle` and four `line` calls per frame** — three
#     captions and four crate counters, then one circle and one spoke for each of
#     the four movers;
#   - **478 `rotated` pushes**, which is two of the four movers across 240 frames
#     less the first one. `Node2D#draw` pushes a rotation only for a node whose
#     angle is not zero, and both spinners start at zero. The two that do not
#     spin never push one at all;
#   - **translates spanning y -16..496**, the world's 480 plus the wrap margin of
#     one radius at each end. That is `Components::ScreenWrap` against the scene's
#     `Components::World`, and it is why nothing is ever seen jumping;
#   - **exactly one clip per frame**, the presentation's. Collision pushes
#     nothing: it is arithmetic over registered shapes and never touches the
#     renderer.
#
# Nothing here needs a seed — the drifters' velocities are a fixed table and the
# timestep is fixed, so two runs at one tick budget agree tick for tick.

idle 5
hold controls::KEY_UP, 25     # up into the crate's band, still left of it
hold controls::KEY_RIGHT, 20  # arrive — visit 1
hold controls::KEY_LEFT, 25   # and leave again
hold controls::KEY_RIGHT, 25  # visit 2
hold controls::KEY_LEFT, 30   # away, while the drifter falls through the crate
idle 50
hold controls::KEY_RIGHT, 30  # back once the crate is untouched again — visit 3
idle 60
