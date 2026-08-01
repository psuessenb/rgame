# frozen_string_literal: true

require 'rgame/core_ext'
require_relative '../util/controls'

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
    # The id vocabulary itself lives in RGame::Util::Controls, not here: ids are
    # values, and the engine layer must be able to name one without touching
    # Core. That is also what makes rebinding possible — a game builds its own
    # table from those constants and passes it in:
    #
    #   controls = RGame::Util::Controls
    #   input = RGame::Core::Input.new(
    #     app, bindings: controls::DEFAULT_KEYBOARD.merge(fire: controls::KEY_J)
    #   )
    #
    # Devices are numbered keyboard-first: Controls::KEYBOARD is 0, and
    # Controls.gamepad(slot) is the pad in that player slot. Defaulting
    # `device:` to the keyboard is what lets single-player call sites stay
    # `input.down?(:fire)` with no ceremony.
    #
    # There is no pointer/mouse support, by design — see
    # docs/plans/gosu-replacement/.
    class Input
      Controls = RGame::Util::Controls

      # `bindings` covers the keyboard, `pad_bindings` the controllers, and
      # `axis_bindings` the analog axes. All default to the standard tables.
      def initialize(app,
                     bindings: Controls::DEFAULT_KEYBOARD,
                     pad_bindings: Controls::DEFAULT_PAD,
                     axis_bindings: Controls::DEFAULT_AXES)
        @app = app
        @bindings = bindings
        @pad_bindings = pad_bindings
        @axis_bindings = axis_bindings
      end

      # Is the action's physical button held on `device`?
      #
      # Reads the engine's per-frame input snapshot, so the answer is identical
      # for every simulation tick within one frame — a key held for a single
      # frame behaves the same whether that frame ran one catch-up tick or five.
      # hot-path
      def down?(action, device: Controls::KEYBOARD)
        @app.input_down?(device, bindings_for(device).fetch(action))
      end

      # Current value of an analog axis: sticks -1.0..1.0, triggers 0.0..1.0.
      # The keyboard has no axes, so it always reads 0.0.
      # hot-path
      def axis(action, device: Controls::KEYBOARD)
        @app.input_axis(device, @axis_bindings.fetch(action))
      end

      private

      # hot-path
      def bindings_for(device)
        device == Controls::KEYBOARD ? @bindings : @pad_bindings
      end
    end
  end
end
