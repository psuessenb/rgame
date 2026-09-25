# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # Integrates linear and angular velocity into the node's transform each step.
      # Free-moving entities (rocks, bullets) use it alone; a controller component
      # (or the node's own control hook) writes vx/vy/spin as intent.
      #
      # A Mover, so `blocked_by:` stops it the way it stops a CharacterBody — see Mover's
      # header. A blocked step keeps `vx`/`vy` as they were: they are the intent, and what
      # a stop should do to them (nothing, zero them, bounce) is the game's call, made in
      # an `on_blocked` handler.
      class Velocity < Mover
        sealed_accessor :vx, :vy, :spin

        def initialize(vx: 0.0, vy: 0.0, spin: 0.0, blocked_by: [], pushes: [])
          super(blocked_by:, pushes:)
          @rgame_vx = vx
          @rgame_vy = vy
          @rgame_spin = spin
        end

        # The velocity scaled so its larger axis is ±1 — the direction, without the square
        # root a unit vector would cost.
        def heading_x = scale_to_heading(@rgame_vx)
        def heading_y = scale_to_heading(@rgame_vy)

        private

        def scale_to_heading(axis)
          larger = [@rgame_vx.abs, @rgame_vy.abs].max
          larger.zero? ? 0.0 : axis / larger.to_f
        end

        def take_step(dt)
          apply_move(@rgame_vx * dt, @rgame_vy * dt)
          node.angle += @rgame_spin * dt
        end
      end
    end
  end
end
