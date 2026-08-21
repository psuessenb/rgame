# frozen_string_literal: true

require 'rgame/core_ext'
require_relative '../util/controls'

module RGame
  module Core
    # Asks the engine whether a physical input is active, on a given device.
    #
    #   input = RGame::Core::Input.new(app)
    #   input.down?(Controls::KEY_SPACE)                          # keyboard
    #   input.down?(Controls::PAD_A, device: Controls.gamepad(0))  # player 1's pad
    #   input.axis(Controls::AXIS_LEFT_X, device: Controls.gamepad(0))
    #
    # **This is the raw query, and deliberately nothing more.** It used to carry
    # binding tables of its own — `down?(:fire)` resolved `:fire` to a scancode
    # through one of three tables passed to the constructor. Those are gone, and
    # binding now lives one layer up in RGame::Engine::InputMap, for two
    # reasons. A game's rebinding screen has to be able to edit the table, and
    # the engine layer may not name RGame::Core at all; and with a player per
    # device, the table is a per-player value rather than a property of the one
    # object that talks to the hardware.
    #
    # What is left is an argument-order adapter over the app's own
    # `input_down?(device, id)` / `input_axis(device, axis_id)`. It stays a named
    # class rather than collapsing into those, because it is what gets handed to
    # the engine layer as an input backend — and handing it a whole App, which
    # can also close the window and rename it, would be a worse seam.
    #
    # Ids come from RGame::Util::Controls. They are values with nothing behind
    # them, so both layers can name one.
    #
    # **There is no pointer or mouse support, by design.** The layer this
    # replaced had a cursor position and a click button riding the same "is
    # held" path as keys, and none of it was carried over: this engine's input
    # is keyboard and controllers. The intended answer for menus is keyboard and
    # controller navigation instead.
    class Input
      Controls = RGame::Util::Controls

      def initialize(app)
        @app = app
      end

      # Is `id` held on `device`?
      #
      # Reads the engine's per-frame input snapshot, so the answer is identical
      # for every simulation tick within one frame — a key held for a single
      # frame behaves the same whether that frame ran one catch-up tick or five.
      #
      # A device only answers for its own kind of input: asking a gamepad about
      # a keyboard scancode is `false`, never the keyboard's answer. That is
      # what lets one binding table list a key and a pad button for the same
      # action and still keep player two's pad from echoing player one.
      # hot-path
      def down?(id, device: Controls::KEYBOARD)
        @app.input_down?(device, id)
      end

      # Current value of an analog axis: sticks -1.0..1.0, triggers 0.0..1.0.
      # The keyboard has no axes, so it always reads 0.0.
      #
      # No dead zone is applied here — this is the hardware's answer. Ignoring
      # a resting stick's jitter is RGame::Engine::ActionMapper's job.
      # hot-path
      def axis(axis_id, device: Controls::KEYBOARD)
        @app.input_axis(device, axis_id)
      end
    end
  end
end
