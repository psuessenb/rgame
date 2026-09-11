# Input script for examples/signals.
#
# Presses the plate four times, so the door ends where it started, then holds
# each of the repeater's two keys for the same span and finally both together.
#
# What the report should show:
#
#   - **one `circle` per frame, and two in the frames after a plate press.** The
#     lamp always draws its body and draws a glow disc only while the glow is
#     above zero, so the extra circles are exactly the fading tail of each press.
#     Four presses at a 1.6-per-second fade come to a little over a hundred extra
#     circles in a 320-tick run;
#   - **the door's leaf reversing direction four times and never in between.** One
#     press toggles it. The door and the lamp react to the same emit, and neither
#     is named anywhere inside the plate — which is the whole example;
#   - **the last `rect` of the run at (51, 26, 12, 12)**: the fourth pip of the
#     `poke` row, which is drawn after the `fire` row every frame and so is always
#     the final draw. The `fire` row ends visibly longer;
#   - three `text` calls and a backdrop, a plate and a door frame per frame, flat
#     throughout.
#
# **The two rates are the payload doing its job**, and they are worth checking in
# isolation, because the combined run hides them in one total. Holding each key
# alone for 100 ticks:
#
#   ruby tools/drive_test_project.rb examples/signals/main.rb --script <one-key script>
#
# gives **8 pips for `fire`** (a 0.20s cooldown) and **3 for `poke`** (0.55s) —
# the ratio of the cooldowns, off one component and one signal. The combined
# script yields one more of each than its held ticks alone would, because a
# cooldown keeps running down through the idle between two holds, so the first
# press after a gap fires at once.
#
# Enter is deliberately the only plate key: Space is `fire` here, and a plate
# reading `ui_confirm` would be pressed by it too. See the input map note in the
# example.

idle 10
press controls::KEY_RETURN   # open
idle 25
press controls::KEY_RETURN   # close
idle 25
press controls::KEY_RETURN   # open again
idle 15
press controls::KEY_RETURN   # and close, so the leaf ends where it started
idle 20

hold controls::KEY_SPACE, 60 # fire, the short cooldown
idle 10
hold controls::KEY_E, 60     # poke, the long one, for the same span
idle 10
hold [controls::KEY_SPACE, controls::KEY_E], 40 # both at once, one component
idle 20
