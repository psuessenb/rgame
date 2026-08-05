# frozen_string_literal: true

module Engine
  module Components
    # Inertial "ship" flight on top of a Velocity sibling: a turn axis rotates the
    # node (angular velocity) and a thrust axis accelerates it along its heading,
    # with optional drag and a top-speed clamp. Reads intent in `control` and
    # integrates it in `update`, so it composes with the normal phase order.
    #
    # Heading convention: angle 0 points along +x ("right"), so forward is
    # (cos θ, sin θ) — consistent with Gosu's clockwise rotation under a y-down screen
    # (e.g. +90° faces down). Firing is intentionally NOT here — see ActionTrigger +
    # the owning node, which knows its muzzle geometry.
    class ThrustController < Engine::Component
      def initialize(turn_speed:, accel:, max_speed:, drag: 0.0,
                     turn_action: :turn, thrust_action: :thrust)
        super()
        @turn_speed = turn_speed
        @accel = accel
        @max_speed = max_speed
        @drag = drag
        @turn_action = turn_action
        @thrust_action = thrust_action
        @thrust = 0.0
      end

      # The Velocity sibling is only guaranteed present once attached to a node.
      def on_attach = @velocity = node.get_component(Velocity)

      def control(actions)
        @velocity.spin = actions.axis(@turn_action) * @turn_speed
        @thrust = actions.axis(@thrust_action)
      end

      def update(dt)
        if @thrust != 0.0
          @velocity.vx += Math.cos(node.angle) * @accel * @thrust * dt
          @velocity.vy += Math.sin(node.angle) * @accel * @thrust * dt
        end
        apply_drag(dt) if @drag.positive?
        clamp_speed
      end

      private

      def apply_drag(dt)
        factor = 1.0 - (@drag * dt)
        factor = 0.0 if factor.negative?
        @velocity.vx *= factor
        @velocity.vy *= factor
      end

      def clamp_speed
        speed = Math.hypot(@velocity.vx, @velocity.vy)
        return unless speed > @max_speed

        scale = @max_speed / speed
        @velocity.vx *= scale
        @velocity.vy *= scale
      end
    end
  end
end
