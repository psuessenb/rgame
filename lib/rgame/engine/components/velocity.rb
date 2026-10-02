# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # Integrates acceleration into the velocity, and the velocity into the node's
      # transform, each step. Free-moving entities (rocks, bullets) use it alone. A
      # controller component, or the node's own control hook, writes vx/vy/spin or
      # ax/ay as intent.
      #
      # A step first adds `ax`/`ay` to the velocity, then takes `drag` off it, then
      # clamps it to `max_speed`, and only then moves the node. So whatever sets the
      # acceleration in `_control` moves the node in this same tick, wherever it sits in
      # the component list. ThrustController sets it that way.
      #
      # A Mover, so `blocked_by:` stops it the way it stops a CharacterBody — see Mover's
      # header. A blocked step keeps `vx`/`vy` as they were: they are the intent, and what
      # a stop should do to them (nothing, zero them, bounce) is the game's call, made in
      # an `on_blocked` handler.
      class Velocity < Mover
        sealed_accessor :vx, :vy, :spin, :ax, :ay

        # Each step keeps `1 - drag * dt` of the velocity, and none once that falls below
        # zero. `max_speed` caps the speed a step leaves it with, and nil caps nothing.
        def initialize(vx: 0.0, vy: 0.0, spin: 0.0, ax: 0.0, ay: 0.0, drag: 0.0, max_speed: nil,
                       blocked_by: [], pushes: [])
          super(blocked_by:, pushes:)
          @rgame_vx = vx
          @rgame_vy = vy
          @rgame_spin = spin
          @rgame_ax = ax
          @rgame_ay = ay
          @rgame_drag = drag
          @rgame_max_speed = max_speed
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
          accelerate(dt) unless @rgame_ax.zero? && @rgame_ay.zero?
          apply_drag(dt) if @rgame_drag.positive?
          clamp_speed if @rgame_max_speed
          apply_move(@rgame_vx * dt, @rgame_vy * dt)
          node.angle += @rgame_spin * dt
        end

        def accelerate(dt)
          @rgame_vx += @rgame_ax * dt
          @rgame_vy += @rgame_ay * dt
        end

        def apply_drag(dt)
          factor = 1.0 - (@rgame_drag * dt)
          factor = 0.0 if factor.negative?
          @rgame_vx *= factor
          @rgame_vy *= factor
        end

        def clamp_speed
          speed = Math.hypot(@rgame_vx, @rgame_vy)
          return unless speed > @rgame_max_speed

          scale = @rgame_max_speed / speed
          @rgame_vx *= scale
          @rgame_vy *= scale
        end
      end
    end
  end
end
