# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # A jump in a top-down view. Pressing the action lifts the node along a
      # parabola that peaks at `peak` pixels halfway through `duration` seconds,
      # then puts it back where it started.
      #
      # The height goes on top of Node2D#elevation, never on `y`. In a top-down
      # view a jump is a *drawing* offset: the sprite arcs above the spot the
      # character stands on, while that spot, and every collider and camera reading
      # it, stays on the ground. So a hop does not carry anyone over a wall. What it
      # crosses is the game's decision, made by reading `airborne?`.
      #
      #   node.add_component(Engine::Components::Hop.new(peak: 18, duration: 0.5))
      #
      # Each hop starts from the elevation the node has as it leaves the ground, and
      # gives that elevation back as it lands. A node a game has raised to elevation 4
      # hops from 4 and lands on 4. The Hop leaving its node, or the node leaving the
      # tree, lands the node too, so a pooled node reused mid-hop starts where it
      # stood. The Hop sets the elevation on every tick of a hop, so a write from
      # elsewhere in mid-air lasts until its next update.
      #
      # The arc is an Engine::Tween with the `:arc` ease, advanced in `update`
      # rather than read off a clock, so a paused node hangs in the air and a
      # spec can ask for the height at 0.25s.
      # It starts on the action's press edge, so holding the button hops once.
      # `action: nil` leaves only #jump, for something that is not a player.
      class Hop < Engine::Component
        # How far the hop has lifted the node above the elevation it started from,
        # in pixels: 0.0 on the ground.
        sealed_reader :height

        def initialize(peak:, duration:, action: :jump)
          super()
          raise ArgumentError, "peak must be positive, got #{peak.inspect}" unless peak.positive?
          raise ArgumentError, "duration must be positive, got #{duration.inspect}" unless duration.positive?

          @rgame_arc = Engine::Tween.new(duration, to: peak, ease: :arc)
          @rgame_action = action
          @rgame_height = 0.0
          @rgame_airborne = false
          @rgame_found = 0
        end

        def peak = @rgame_arc.to
        def duration = @rgame_arc.duration

        def airborne? = @rgame_airborne

        # Leave the ground, from the elevation the node has now. Does nothing while
        # already off it; `airborne?` says which.
        def jump
          return if @rgame_airborne

          @rgame_airborne = true
          @rgame_found = node.elevation
          @rgame_arc.restart
        end

        def _control(actions)
          jump if @rgame_action && actions.pressed?(@rgame_action)
        end

        def _update(dt)
          return unless @rgame_airborne
          return land if @rgame_arc.update(dt).done?

          @rgame_height = @rgame_arc.value
          node.elevation = @rgame_found + @rgame_height
        end

        # Lands a node in the air, giving back the elevation it hopped from, as the
        # Hop leaves its node or the node leaves the tree.
        def _detach
          land if @rgame_airborne
        end

        private

        def land
          @rgame_airborne = false
          @rgame_height = 0.0
          node.elevation = @rgame_found
        end
      end
    end
  end
end
