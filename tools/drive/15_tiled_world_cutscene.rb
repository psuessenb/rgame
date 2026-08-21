# Cutscene script for examples/15_tiled_world.
#
# The acceptance test for step 5. Player one walks; player two joins on a pad
# and walks the other way, so the screen splits into two viewports with two
# different cameras. Then either player presses the cutscene button: the split
# collapses to one screen-wide view, the world freezes, and a panel draws over
# it. Pressing again resumes.
#
# What the report should show: the two half-height clips stop appearing while
# the cutscene is open, the full-screen clip takes over, and `nine_slice`
# appears — for the first time in any example.

on controls::KEYBOARD do
  idle 10
  hold controls::KEY_RIGHT, 60
  idle 5
  press controls::KEY_TAB          # open the cutscene
  idle 60                          # the world is frozen for these ticks
  press controls::KEY_TAB          # and resumes
  hold controls::KEY_UP, 50
  idle 20
end

on controls.gamepad(0) do
  idle 20
  press controls::PAD_A            # join: seats player two, splits the screen
  idle 5
  hold controls::PAD_DPAD_LEFT, 45
  idle 130                         # frozen through the cutscene, then idle
end
