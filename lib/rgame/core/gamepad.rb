# frozen_string_literal: true

require 'rgame/core_ext'
require_relative '../util/controls'

module RGame
  module Core
    # Which controllers are plugged in, and what they are called.
    #
    #   pads = RGame::Core::Gamepad.new(app)
    #   pads.count                  # => 1
    #   pads.connected?(0)          # => true
    #   pads.name(0)                # => "Xbox Controller"
    #
    # This is a readout for menus — "Player 2: connect a controller" — not part
    # of the frame path; reading a *button* goes through RGame::Core::Input.
    #
    # Slots are player slots, stable across a momentary unplug: a pad that falls
    # out and comes back returns to the slot it had, so player 2 stays player 2.
    # The engine reports arrivals and departures through the App's
    # `gamepad_connected` / `gamepad_disconnected` callbacks; this class answers
    # the same question by polling, which is what a menu redraw wants.
    class Gamepad
      Controls = RGame::Util::Controls

      def initialize(app)
        @app = app
      end

      # How many controllers are currently connected.
      def count = @app.gamepad_count

      # The number of player slots the engine supports, connected or not — the
      # bound for a "controller setup" screen's loop.
      def max_slots = Controls::MAX_GAMEPADS

      def connected?(slot) = @app.gamepad_present?(slot)

      # Human-readable name of the pad in `slot`, or nil when the slot is empty.
      def name(slot) = @app.gamepad_name(slot)

      # The input device id for a slot, so a menu that just found a pad can hand
      # the right device to Input without knowing how devices are numbered.
      def device(slot) = Controls.gamepad(slot)

      # Yields [slot, name] for each connected pad, lowest slot first. Allocates
      # nothing, so it is safe to call from a menu that redraws every frame.
      def each_connected
        return enum_for(:each_connected) unless block_given?

        max_slots.times { |slot| yield slot, name(slot) if connected?(slot) }
      end
    end
  end
end
