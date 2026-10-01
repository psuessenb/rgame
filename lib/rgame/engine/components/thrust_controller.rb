# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # Inertial "ship" flight on top of a Velocity sibling: a turn axis rotates the
      # node (angular velocity) and a thrust axis accelerates it along its heading.
      # It writes only in `_control`, setting the Velocity's `spin` and its `ax`/`ay`,
      # and the Velocity integrates both in its own step. So the first thrust moves the
      # ship on the tick it starts, in either add order. Drag and the top speed are the
      # Velocity's `drag:` and `max_speed:`.
      #
      # Heading convention: angle 0 points along +x ("right"), so forward is
      # (cos θ, sin θ) — consistent with the renderer's clockwise rotation under a y-down screen
      # (e.g. +90° faces down). Thrust follows the heading the node has when `_control`
      # runs, before that tick's turn. Firing is intentionally NOT here — see ActionTrigger +
      # the owning node, which knows its muzzle geometry.
      class ThrustController < Engine::Component
        def initialize(turn_speed:, accel:, turn_action: :turn, thrust_action: :thrust)
          super()
          @rgame_turn_speed = turn_speed
          @rgame_accel = accel
          @rgame_turn_action = turn_action
          @rgame_thrust_action = thrust_action
        end

        # Finds the Velocity sibling, which is only guaranteed present once attached to
        # a node, and keeps the spin and acceleration it had for `_detach` to give back.
        def _attach
          @rgame_velocity = require_sibling(Velocity)
          @rgame_found_spin = @rgame_velocity.spin
          @rgame_found_ax = @rgame_velocity.ax
          @rgame_found_ay = @rgame_velocity.ay
        end

        # Gives the Velocity back the spin and acceleration it had at attach, so a ship
        # whose controller is gone drifts rather than turning and thrusting on.
        def _detach
          @rgame_velocity.spin = @rgame_found_spin
          @rgame_velocity.ax = @rgame_found_ax
          @rgame_velocity.ay = @rgame_found_ay
        end

        def _control(actions)
          @rgame_velocity.spin = actions.axis(@rgame_turn_action) * @rgame_turn_speed
          thrust = actions.axis(@rgame_thrust_action)
          return coast if thrust.zero?

          @rgame_velocity.ax = Math.cos(node.angle) * @rgame_accel * thrust
          @rgame_velocity.ay = Math.sin(node.angle) * @rgame_accel * thrust
        end

        private

        def coast
          @rgame_velocity.ax = 0.0
          @rgame_velocity.ay = 0.0
        end
      end
    end
  end
end
