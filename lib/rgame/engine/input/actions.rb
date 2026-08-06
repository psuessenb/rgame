# frozen_string_literal: true

module RGame
  module Engine
    # An immutable per-frame snapshot of abstract action state. Game logic reads
    # this, never physical keys. Built by ActionMapper (or constructed directly in
    # tests with a fake).
    #
    # Edge queries (`pressed?`/`released?`) compare against the previous frame's held
    # state, so a one-shot action (menu confirm, jump) fires exactly once per press
    # rather than every frame it's held.
    class Actions
      # `held`, `axes` and `prev_held` are mutable hashes the mapper updates in place
      # each poll, so the snapshot stays a single reused, allocation-free object.
      def initialize(held: {}, axes: {}, prev_held: {})
        @held = held
        @axes = axes
        @prev_held = prev_held
      end

      def held?(name)
        @held.fetch(name, false)
      end

      # True only on the frame the action transitions up→down.
      def pressed?(name)
        @held.fetch(name, false) && !@prev_held.fetch(name, false)
      end

      # True only on the frame the action transitions down→up.
      def released?(name)
        !@held.fetch(name, false) && @prev_held.fetch(name, false)
      end

      # Analog value in [-1.0, 1.0]; 0.0 if unbound/neutral.
      def axis(name)
        @axes.fetch(name, 0.0)
      end
    end
  end
end
