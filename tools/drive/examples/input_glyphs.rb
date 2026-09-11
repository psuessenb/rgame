# Input script for examples/input_glyphs.
#
# Two absolute timelines, and the point is the hand-offs between them. The
# keyboard starts with the seat; at tick 60 the controller presses A and takes
# it; at tick 130 the keyboard presses Enter and takes it back; at tick 180 the
# controller takes it again. Each of them also walks the hero while it holds the
# seat, so the run shows the prompts and the movement following the same device.
#
# What the report should show:
#
#   - **the last `sprite` call, which is the whole acceptance test.** The panel is
#     the last child of the scene and the `Wave` row is the last thing it draws,
#     so the last `sprite` of the run is that row's glyph — and its column says
#     which device the panel was reading. Run the same script at four budgets:
#
#         --ticks  40  →  last("glyphs.json", 0, 0, 14, 178)   column 0, Space
#         --ticks 100  →  last("glyphs.json", 0, 3, 14, 178)   column 3, A
#         --ticks 150  →  last("glyphs.json", 0, 0, 14, 178)   column 0, Space
#         --ticks 240  →  last("glyphs.json", 0, 3, 14, 178)   column 3, A
#
#     which is the seat going keyboard, controller, keyboard, controller. The
#     third of those is the one worth having: takeover handing the seat *back* to
#     the keyboard is the open question this example was written to answer, and
#     column 0 at 150 ticks is the answer;
#   - **four `sprite` calls per frame** — the hero, and one glyph per prompt row.
#     All three rows resolve to a glyph on both kinds of device, so the count does
#     not move when the seat does;
#   - **six `text` calls per frame** — two captions, the device name, and three
#     row labels;
#   - **two `rect` calls per frame**, the backdrop and the panel. Nothing here is
#     a menu: the panel is a rectangle and the prompts are sprites;
#   - **one clip per frame**, the presentation's. One player, one full-window
#     viewport, no `WorldView` — this example is entirely screen space.
#
# `--gamepad` does not apply. That mode points the player at slot 0 from the
# start and leaves the real backend in place, so there is no keyboard seat to
# hand over and nothing switches.

on controls::KEYBOARD do
  idle 20
  hold controls::KEY_RIGHT, 30 # walking on the keyboard
  idle 80
  press controls::KEY_RETURN   # ui_confirm on an unassigned keyboard: the seat comes back
  idle 108
end

on controls.gamepad(0) do
  idle 60
  press controls::PAD_A            # ui_confirm on an unassigned pad: takeover
  idle 8
  hold controls::PAD_DPAD_DOWN, 40 # and the same hero walks on the pad
  idle 70
  press controls::PAD_A            # takes it again, so the run ends on the controller
  idle 58
end
