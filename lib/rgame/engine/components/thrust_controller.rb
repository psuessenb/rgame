# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # Inertial "ship" flight on top of a Velocity sibling: a turn axis rotates the
      # node (angular velocity) and a thrust axis accelerates it along its heading,
      # with optional drag and a top-speed clamp. Reads intent in `_control` and
      # integrates it in `_update`, so it composes with the normal phase order.
      #
      # Heading convention: angle 0 points along +x ("right"), so forward is
      # (cos θ, sin θ) — consistent with the renderer's clockwise rotation under a y-down screen
      # (e.g. +90° faces down). Firing is intentionally NOT here — see ActionTrigger +
      # the owning node, which knows its muzzle geometry.
      class ThrustController < Engine::Component
        def initialize(turn_speed:, accel:, max_speed:, drag: 0.0,
                       turn_action: :turn, thrust_action: :thrust)
          super()
          @rgame_turn_speed = turn_speed
          @rgame_accel = accel
          @rgame_max_speed = max_speed
          @rgame_drag = drag
          @rgame_turn_action = turn_action
          @rgame_thrust_action = thrust_action
          @rgame_thrust = 0.0
        end

        # The Velocity sibling is only guaranteed present once attached to a node.
        def _attach = @rgame_velocity = require_sibling(Velocity)

        def _control(actions)
          @rgame_velocity.spin = actions.axis(@rgame_turn_action) * @rgame_turn_speed
          @rgame_thrust = actions.axis(@rgame_thrust_action)
        end

        def _update(dt)
          if @rgame_thrust != 0.0
            @rgame_velocity.vx += Math.cos(node.angle) * @rgame_accel * @rgame_thrust * dt
            @rgame_velocity.vy += Math.sin(node.angle) * @rgame_accel * @rgame_thrust * dt
          end
          apply_drag(dt) if @rgame_drag.positive?
          clamp_speed
        end

        private

        def apply_drag(dt)
          factor = 1.0 - (@rgame_drag * dt)
          factor = 0.0 if factor.negative?
          @rgame_velocity.vx *= factor
          @rgame_velocity.vy *= factor
        end

        def clamp_speed
          speed = Math.hypot(@rgame_velocity.vx, @rgame_velocity.vy)
          return unless speed > @rgame_max_speed

          scale = @rgame_max_speed / speed
          @rgame_velocity.vx *= scale
          @rgame_velocity.vy *= scale
        end
      end
    end
  end
end
