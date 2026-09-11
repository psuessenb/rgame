# Two-player input script for examples/split_screen.
#
# Player one is on the keyboard from the start and the second seat is empty, so
# the game opens as an ordinary full-screen one-player session. Thirty ticks in a
# controller presses A: player two is seated, their walker and badge appear, and
# the screen splits. Then the two walk in opposite directions, and each of them
# waves — player one twice, player two once.
#
# Tracks are absolute and independent: both players act at the same time, not in
# turn.
#
# What the report should show:
#
#   - **three clip rectangles, and which ones tell the whole story.** The full
#     window is clipped 302 times: 240 of those are the presentation's, once a
#     frame whatever else happens, and the other 62 are the 31 frames before the
#     join, where the single active player's viewport and their own layer are both
#     the whole window. Then `[0, 0, 640, 240]` and `[0, 240, 640, 240]` appear
#     418 times each — the two halves, twice per frame for 209 frames, once for the
#     world drawn through that player's camera and once for their own screen
#     space. Nothing in the example asked for any of this;
#   - **the last `text` reading `waves: 1`.** That is player two's badge, and it
#     is the ownership test. Player one pressed Space twice on the keyboard, and
#     if either subtree were reading the other's device — or the raw input rather
#     than their player's — it would read 3;
#   - **499 `sprite` calls**, which is 31 frames of one walker, 209 frames of two
#     viewports each drawing the walkers it can see, and about 25 frames after the
#     join in which *both* halves could still see both of them. They start side by
#     side, so each is in the other's view until they separate, and
#     `Engine::Culling` drops the draw after that. A world drawn twice with nothing
#     culled would be a flat 4 per frame;
#   - **898 layers in the `:hud` band against 2005 in `:world`.** The hud ones are
#     the player layers and their badges, which exist once per active player per
#     frame rather than once per viewport — a player's own screen space is the
#     third kind of content, and it is drawn once for them;
#   - **no audio and no scenes.** This example has one scene and never pushes
#     another.
#
# `--gamepad` does not apply here. That mode points player one at slot 0 and
# leaves the real backend in place, so there is no unassigned device for anybody
# to join with, and the run stays one player wide.

on controls::KEYBOARD do
  idle 10
  hold controls::KEY_UP, 40
  press controls::KEY_SPACE   # wave
  press controls::KEY_SPACE   # and again — player one's badge reads 2
  hold controls::KEY_UP, 60
  idle 60
end

on controls.gamepad(0) do
  idle 30
  press controls::PAD_A       # join: seats player two, splits the screen
  idle 20
  hold controls::PAD_DPAD_DOWN, 90 # the other way, so the two halves diverge
  press controls::PAD_A       # wave — player two's badge reads 1
  idle 40
end
