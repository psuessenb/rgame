# Input script for examples/cutscene, watched to the end. Run it for its whole
# length:
#
#   ruby tools/drive_test_project.rb examples/cutscene/main.rb --texts --ticks 720
#
# The pad joins, so the screen splits. Player one presses E, and the cutscene
# runs: half a second, the crier's walk to the square, two lines of news, and a
# press. Return turns the box's page, ends the conversation, and answers the
# press. Then each player walks a little, to show both heroes run again.
#
# What the report should show:
#
#   - **"The garden gate is shut" to tick 506, and "The garden gate is open"
#     from tick 507**, the tick after the press;
#   - **"Town crier" and the first line from tick 391**, as the walk ends, and
#     the second line from tick 423;
#   - **252 clips of each half of the window**, `[0, 0, 640, 240]` and `[0,
#     240, 640, 240]`: the split before the cutscene and after it. Everything
#     between draws into one clip of the whole window, `[0, 0, 640, 480]`;
#   - **the last `tilemap` call reading `("town.tmx", 1, 104.0, 88.7, 640,
#     240)`**, player two's view after their walk. `cutscene_skip.rb` ends on
#     the same call;
#   - **no audio.**
#
# Under `--allocations`, about 63 objects a second, on 2% of ticks. Putting up
# the crier's box builds a menu, a label and its pages, and starting the
# cutscene suspends and solos: about 470 objects in one second, and none on any
# other tick. `spec/rgame/engine/components/cutscene_allocation_spec.rb` holds a
# running cutscene to nothing a tick.

allocation_budget objects_per_second: 80

on controls::KEYBOARD do
  idle 60
  press controls::KEY_E
  idle 360
  press controls::KEY_RETURN
  idle 40
  press controls::KEY_RETURN
  idle 40
  press controls::KEY_RETURN
  idle 40
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
