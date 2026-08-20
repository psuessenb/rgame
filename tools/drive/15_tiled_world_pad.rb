# Gamepad script for examples/15_tiled_world — run it with --gamepad.
#
# This is the acceptance test for the input rework. It drives a synthetic SDL
# controller, so nothing is stubbed: the pad's events go through SDL, the C
# per-frame snapshot, RGame::Core::Input, the InputMap and the ActionMapper,
# exactly as a real controller would. Before that rework no gamepad input could
# reach the engine layer at all, and no analog axis could reach it from any
# device.
#
# The dpad half proves buttons and device routing; the stick half proves the
# analog path and the dead zone. A resting stick is deliberately included: it
# reads a small non-zero value on real hardware, and the player must not drift.

idle 20                                  # SDL seats the pad in slot 0

hold controls::PAD_DPAD_RIGHT, 40        # buttons: dpad east
hold controls::PAD_DPAD_DOWN, 40         # and south

tilt controls::AXIS_LEFT_X, 0.05, 20     # inside the dead zone: must not move
tilt controls::AXIS_LEFT_X, 1.0, 40      # analog: full east
tilt controls::AXIS_LEFT_Y, -1.0, 40     # analog: full north
tilt controls::AXIS_LEFT_X, 0.5, 30      # half deflection, so speed is analog

idle 10
