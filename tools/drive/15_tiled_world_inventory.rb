# Per-player inventory script for examples/15_tiled_world.
#
# The acceptance scenario for the whole split-screen rework: **one player
# browsing a menu while the other walks.**
#
# Player one is on the keyboard and walks throughout, without pause. Player two
# joins on a pad, walks a little, then opens their inventory and navigates it —
# and stops moving, because opening it pauses their walker and nothing else.
#
# What the report should show: two viewports drawing the world all the way
# through, `nine_slice` appearing for the menu, and **player one's camera track
# still growing while player two's stops**.

on controls::KEYBOARD do
  idle 10
  hold controls::KEY_RIGHT, 100     # walks the whole time, menu or no menu
  hold controls::KEY_DOWN, 80
  hold controls::KEY_RIGHT, 40
  idle 10
end

on controls.gamepad(0) do
  idle 20
  press controls::PAD_A             # join: seats player two, splits the screen
  idle 5
  hold controls::PAD_DPAD_LEFT, 40  # walks for a bit
  idle 5
  press controls::PAD_B             # ui_cancel: opens their inventory
  idle 10
  press controls::PAD_DPAD_DOWN     # navigate it — this moves focus, not them
  idle 10
  press controls::PAD_DPAD_DOWN
  idle 10
  hold controls::PAD_DPAD_LEFT, 40  # still held down, still going nowhere
  idle 60
end
