# Input script for examples/menu_navigation.
#
# Walks the whole shape of the example: title -> settings, changes all three
# rows, comes back with Escape, then plays, blips, and returns to the title.
#
# It deliberately never activates **Quit**: that closes the game, the loop stops,
# and the run ends before its tick budget with a report that looks like a crash.
# Drive Quit on its own if you want to check it.
#
# What the report should show:
#
#   - **`nine_slice` jumping from 3 per frame to 8 while settings is open.** The
#     title's three menu rows keep drawing the whole time, because settings is
#     *pushed* rather than replacing them — that is the stack, visible as a
#     number. Settings adds its panel and four rows of its own;
#   - **`nine_slice` back to 3 after Escape**, and the title's own `text` still
#     there. It was never taken apart, so there is nothing to rebuild;
#   - **`nine_slice` at 0 during play**, because Play *replaces* the title rather
#     than pushing over it. That contrast is the whole point of the example;
#   - **one `sound blip.ogg`**, from Enter during the play scene. Play fades,
#     and no scene reads input until the fade has revealed the play scene, so
#     the script waits 40 ticks before that Enter;
#   - **62 `rect`s and 60 `faded`, only while Play and Escape fade.** Each
#     transition draws a rect over the whole view in `:overlay` for 31 frames:
#     30 inside `faded`, and one at full cover, the frame the switch lands. The
#     play scene's text starts at tick 211, 16 ticks after the Enter on Play.
#     Settings is pushed and popped with `transition: nil`, so opening and
#     closing it fades nothing;
#   - `scaled` appearing once the scale row is moved off `:disabled`, and a clip
#     per frame with it — the presentation transform, exactly as in
#     `tools/drive/examples/fullscreen.rb`.
#
# The harness gives the run a fresh save directory. That matters here: the
# example loads its settings file before the first frame, so one left by an
# earlier run would change what this script does.
#
#   ruby tools/drive_test_project.rb examples/menu_navigation/main.rb --ticks 320
#
# Under `--allocations` it allocates about 78 objects a second, on 4% of ticks,
# over the default 60. The warm-up ends before Play, so the run measures the
# first transition in the process: about 150 objects filling call caches and
# building the stack's fade. A later transition allocates 5, and a tick while
# one runs allocates nothing, which
# `spec/rgame/engine/scene/scene_stack_transition_spec.rb` holds it to. The
# other 56 a second are the scenes built again as each switch lands.

allocation_budget objects_per_second: 90

idle 15

press controls::KEY_DOWN   # Play -> Settings
idle 8
press controls::KEY_RETURN # push the settings screen over the title
idle 15

press controls::KEY_RIGHT  # Fullscreen: off -> on
idle 20
press controls::KEY_LEFT   # and back to off, so the rest of the run is windowed
idle 15

press controls::KEY_DOWN   # Scale mode
idle 8
press controls::KEY_RIGHT  # :disabled -> :stretch, so `scaled` appears
idle 20
press controls::KEY_RIGHT  # -> :letterbox
idle 20

press controls::KEY_DOWN   # Volume
idle 8
press controls::KEY_LEFT   # 75% -> 50%
idle 15

press controls::KEY_ESCAPE # pop back to the title, which never stopped drawing
idle 20

press controls::KEY_UP     # Settings -> Play
idle 8
press controls::KEY_RETURN # replaces the title, under a fade
idle 40                    # the fade covers and reveals; nothing reads input until it ends

press controls::KEY_RETURN # blip, at the volume set above
idle 20

press controls::KEY_ESCAPE # back to the title, under a fade
idle 40
