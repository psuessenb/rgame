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
        attr_accessor :vx, :vy, :spin

        def initialize(vx: 0.0, vy: 0.0, spin: 0.0, blocked_by: [])
          super(blocked_by: blocked_by)
          @vx = vx
          @vy = vy
          @spin = spin
        end

        private

        # The angle is written straight to the node whatever was declared: a collision box
        # does not turn with its node, so there is nothing for a rotation to be blocked by.
        def take_step(dt)
          apply_move(@vx * dt, @vy * dt)
          node.angle += @spin * dt
        end
      end
    end
  end
end
