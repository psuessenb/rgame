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
# factors depend on that rather than on this script.
#
# **`:stretch` cannot be told from `:letterbox` in this run, and that is the
# harness rather than a bug.** They differ only when the window's aspect ratio
# differs from the game's, and the harness runs an 800x600 screen against a
# 640x480 game — both 4:3, so both modes land on the same uniform 1.25x. On a
# 16:9 display stretch scales the axes by different factors and the circle goes
# oval. The arithmetic for that case is covered where it can be pinned down
# exactly: spec/rgame/engine/presentation_spec.rb asserts 2.5 against 1.875 for
# a 1600x900 window.

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
