# Input script for examples/fullscreen.
#
# Cycles right through all four scale modes, back one, then toggles fullscreen
# and cycles again — so every mode is exercised both windowed and fullscreen.
#
# What the report should show:
#
#   - **`scaled` appearing at all.** That call is the presentation transform, and
#     it exists only under a scaling mode: `:disabled` pushes none. Its arguments
#     are the two scale factors;
#   - **a `clip` per frame once a scaling mode is on**, and none while
#     `:disabled` — that clip is what makes the letterbox bars bars rather than
#     somewhere the game can draw;
#   - `line`, `rect` and `circle` coordinates that stop moving as soon as a
#     scaling mode is on. Under `:disabled` they follow the window, because the
#     scene reads `view.width`; under the others the view is a fixed 640x480 and
#     the *transform* does the work instead. That swap is the point of the
#     example, and it is visible as numbers here.
#
# The window size under Xvfb is whatever the harness started, so the exact scale
# factors depend on that rather than on this script. The offsets above are the
# letterbox bars and the integer-mode margin, and they are the other half of what
# the clip section shows.
#
# **All three scaling modes are distinguishable in this run**, which is what the
# game's 8:5 logical size buys. The harness opens an 800x600 window, so:
#
#   stretch    1.5625 x 1.8750   offset   0,   0
#   letterbox  1.5625 x 1.5625   offset   0,  50
#   integer    1.0000 x 1.0000   offset 144, 140
#
# Three different `scaled` argument pairs and three different clip rectangles, so
# a mode that stopped working is visible here rather than only on a real display.
# A 4:3 game would not show this: against a 4:3 window stretch and letterbox
# compute the same uniform factor and the report cannot tell them apart.

idle 20
press controls::KEY_RIGHT # :disabled -> :stretch
idle 25
press controls::KEY_RIGHT # -> :letterbox
idle 25
press controls::KEY_RIGHT # -> :integer
idle 25
press controls::KEY_RIGHT # wraps back to :disabled
idle 25
press controls::KEY_LEFT  # and backwards, to :integer
idle 25

press controls::KEY_F     # fullscreen, still scaled
idle 30
press controls::KEY_LEFT  # -> :letterbox while fullscreen
idle 30
