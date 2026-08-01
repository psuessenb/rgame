# frozen_string_literal: true

require 'rgame/core_ext'

module RGame
  module Core
    # Translates the game's symbolic actions (:fire, :confirm) into the physical
    # button ids the engine understands, and asks the app whether they're held.
    #
    #   input = RGame::Core::Input.new(app)
    #   input.down?(:fire)                 # keyboard, the single-player default
    #   input.down?(:fire, device: 1)      # the pad in player slot 0
    #   input.axis(:move_x, device: 1)     # => Float, -1.0..1.0
    #
    # The id constants (KEY_LEFT, PAD_A, AXIS_LEFT_X, KEYBOARD, ...) come from C
    # so they cannot drift from the engine's own numbering; see
    # ext/rgame_core/core_ext.c. What lives here is the *binding table*, which
    # is configuration — which physical input means "fire" for this game — and
    # reads far better as a Ruby hash than as a C lookup table.
    #
    # Devices are numbered keyboard-first: KEYBOARD is 0, and gamepad(slot) is
    # the pad in that player slot. Defaulting `device:` to KEYBOARD is what lets
    # single-player call sites stay `input.down?(:fire)` with no ceremony.
    #
    # There is no pointer/mouse support, by design — see
    # docs/plans/gosu-replacement/.
    class Input
      # Symbolic action => physical button, per device class. Two tables rather
      # than one because the same action is a different button on each: :fire is
      # the space bar on a keyboard and the A button on a pad.
      KEYBOARD_BINDINGS = {
        left: KEY_LEFT,
        right: KEY_RIGHT,
        up: KEY_UP,
        down: KEY_DOWN,
        confirm: KEY_RETURN,
        fire: KEY_SPACE
      }.freeze

      PAD_BINDINGS = {
        left: PAD_DPAD_LEFT,
        right: PAD_DPAD_RIGHT,
        up: PAD_DPAD_UP,
        down: PAD_DPAD_DOWN,
        confirm: PAD_A,
        fire: PAD_A
      }.freeze

      # Analog axes exist only on pads, so there is one table.
      AXIS_BINDINGS = {
        move_x: AXIS_LEFT_X,
        move_y: AXIS_LEFT_Y,
        aim_x: AXIS_RIGHT_X,
        aim_y: AXIS_RIGHT_Y,
        trigger_left: AXIS_TRIGGER_LEFT,
        trigger_right: AXIS_TRIGGER_RIGHT
      }.freeze

      # The device id for a player slot: gamepad(0) is the first controller.
      def self.gamepad(slot) = GAMEPAD_FIRST + slot

      def initialize(app)
        @app = app
      end

      # Is the action's physical button held on `device`?
      #
      # Reads the engine's per-frame input snapshot, so the answer is identical
      # for every simulation tick within one frame — a key held for a single
      # frame behaves the same whether that frame ran one catch-up tick or five.
      # hot-path
      def down?(action, device: KEYBOARD)
        @app.input_down?(device, bindings_for(device).fetch(action))
      end

      # Current value of an analog axis: sticks -1.0..1.0, triggers 0.0..1.0.
      # The keyboard has no axes, so it always reads 0.0.
      # hot-path
      def axis(action, device: KEYBOARD)
        @app.input_axis(device, AXIS_BINDINGS.fetch(action))
      end

      private

      # hot-path
      def bindings_for(device)
        device == KEYBOARD ? KEYBOARD_BINDINGS : PAD_BINDINGS
      end
    end
  end
end
