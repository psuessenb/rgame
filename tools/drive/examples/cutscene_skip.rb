# Input script for examples/cutscene, skipped during the crier's walk. Run it
# beside cutscene.rb and compare:
#
#   ruby tools/drive_test_project.rb examples/cutscene/main.rb \
#     --script tools/drive/examples/cutscene_skip.rb --texts --ticks 720
#
# The pad joins and player one presses E, as in the watched run. Half a second
# into the walk, player one holds Tab for three quarters of a second, past the
# skip's 0.6. Then each player walks as they do in the watched run.
#
# What the report should show:
#
#   - **"The garden gate is open" from tick 158**, as the skip lands. The walk
#     is finished, the conversation is put up and ended where it stands, the
#     press is passed, and the gate opens in the last step, which a skip runs;
#   - **no "Town crier" and no line of news**: the box is freed in the tick it
#     was built, before anything draws it;
#   - **601 clips of each half of the window**: the split comes back as the skip
#     lands;
#   - **the last `tilemap` call reading `("town.tmx", 1, 104.0, 88.7, 640,
#     240)`**, the watched run's. Both heroes walk as far, and the crier stands
#     at the square, (456, 232), in both runs.

on controls::KEYBOARD do
  idle 60
  press controls::KEY_E
  idle 60
  hold controls::KEY_TAB, 45
  idle 420
  hold controls::KEY_DOWN, 40
  idle 40
end

on controls.gamepad(0) do
  idle 20
  press controls::PAD_A
  idle 580
  hold controls::PAD_DPAD_UP, 40
  idle 40
end
