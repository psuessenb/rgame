# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # A jump in a top-down view. Pressing the action lifts the node along a
      # parabola that peaks at `peak` pixels halfway through `duration` seconds,
      # then puts it back on the ground.
      #
      # The height is written to Node2D#elevation, never to `y`. In a top-down view
      # a jump is a *drawing* offset: the sprite arcs above the spot the character
      # stands on, while that spot, and every collider and camera reading it, stays
      # on the ground. So a hop does not carry anyone over a wall. What it
      # crosses is the game's decision, made by reading `airborne?`.
      #
      #   node.add_component(Engine::Components::Hop.new(peak: 18, duration: 0.5))
      #
      # The arc is a function of the time accumulated in `update`, not of a clock,
      # so a paused node hangs in the air and a spec can ask for the height at 0.25s.
      # It starts on the action's press edge, so holding the button hops once.
      # `action: nil` leaves only #jump, for something that is not a player.
      class Hop < Engine::Component
        attr_reader :peak, :duration, :height

        def initialize(peak:, duration:, action: :jump)
          super()
          raise ArgumentError, "peak must be positive, got #{peak.inspect}" unless peak.positive?
          raise ArgumentError, "duration must be positive, got #{duration.inspect}" unless duration.positive?

          @peak = peak
          @duration = duration
          @action = action
          @height = 0.0
          @elapsed = 0.0
          @airborne = false
        end

        # Attaching lands the node, so a pooled node reused mid-hop starts on the ground.
        def on_attach = land

        def airborne? = @airborne

        # Leave the ground. Does nothing while already off it; `airborne?` says which.
        def jump
          return if @airborne

          @airborne = true
          @elapsed = 0.0
        end

        def control(actions)
          jump if @action && actions.pressed?(@action)
        end

        def update(dt)
          return unless @airborne

          @elapsed += dt
          return land if @elapsed >= @duration

          @height = 4.0 * @peak * @elapsed * (@duration - @elapsed) / (@duration * @duration)
          node.elevation = @height
        end

        private

        def land
          @airborne = false
          @elapsed = 0.0
          @height = 0.0
          node.elevation = 0
        end
      end
    end
  end
end
