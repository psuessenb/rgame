# Input script for examples/pooling.
#
# Runs pooled, switches to building a fresh mote every spawn, and switches back —
# each stretch long enough for the allocation readout to settle, which takes a
# second or two because it samples once a second.
#
# **The readout is not what this script checks.** Under the harness both modes
# report around eighty-five thousand objects a second, because the harness
# records every draw call with its arguments and that recording is five hundred
# times everything the game allocates. Run the example plainly to see the number
# it is about — 140 a second pooled against 750 fresh. What the report *can*
# show is that the two modes are otherwise identical:
#
#   - **`rect` and translate counts that do not care which mode is on.** The
#     motes are the same motes, attached the same way, updated and drawn by the
#     same traversal. A pooled node is an ordinary child, and the report is where
#     that stops being a claim — if pooling changed the shape of the frame, the
#     counts would step at each Space;
#   - **translates spanning x -30..670 and y -30..510**, which is the window plus
#     the 30-pixel despawn margin on each side. That is `Components::DespawnOffscreen`
#     resolving its bounds through the scene's `Components::World`, exactly as the
#     wrap in `examples/velocity` does, and it is why no mote is ever retired
#     somewhere you could see it happen;
#   - **a live count that climbs and then flattens.** Spawning is a fixed rate and
#     so is leaving the world, so the number on screen settles rather than growing
#     without bound. Flat is the sign the reclaim is working: the free list is
#     being refilled as fast as it is drawn from;
#   - **two `text` calls per frame** — the mode line and the readout — with the
#     readout drawn last, because the meter is a child and a node draws itself
#     before its children.
#
# The spawn directions come off a seeded RNG, so two runs at one tick budget
# match; `--seed N` overrides it.

idle 190
press controls::KEY_SPACE  # fresh objects
idle 190
press controls::KEY_SPACE  # back to the pool
idle 190
