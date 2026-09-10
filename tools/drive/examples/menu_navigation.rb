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
#   - **one `sound blip.ogg`**, from Enter during the play scene;
#   - `scaled` appearing once the scale row is moved off `:disabled`, and a clip
#     per frame with it — the presentation transform, exactly as in
#     `tools/drive/examples/fullscreen.rb`.
#
# Set `RGAME_SAVE_DIR` to somewhere disposable, so the run neither writes into
# the home directory of whoever is running it nor reads settings left by an
# earlier one — the example loads its file before the first frame, so a stale
# one would change what this script does:
#
#   RGAME_SAVE_DIR=/tmp/settings ruby tools/drive_test_project.rb \
#     examples/menu_navigation/main.rb --ticks 320

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
press controls::KEY_RETURN # replaces the title
idle 20

press controls::KEY_RETURN # blip, at the volume set above
idle 20

press controls::KEY_ESCAPE # back to the title
idle 25
