# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # A simple AI driver for a CharacterBody sibling: every so often it rolls a new
      # direction (one of eight, or idle) and holds it until a timer elapses — or until a
      # wall blocks it, at which point it re-rolls early instead of pushing into the wall.
      # The RNG is injected so behaviour is deterministic in tests.
      #
      # "Blocked" is the body's Mover#stopped?: its last step was cut short, on either
      # axis, while it meant to move. So a body declaring no `blocked_by:` is never
      # blocked, and one riding a Components::Platform re-rolls at the platform's edge
      # although the platform carries it every tick.
      class WanderController < Engine::Component
        DIRECTIONS = [
          [-1, 0], [1, 0], [0, -1], [0, 1],
          [-1, -1], [1, -1], [-1, 1], [1, 1]
        ].freeze

        def initialize(rng: Random.new, change_interval: 1.0..3.0, idle_chance: 0.25)
          super()
          @rgame_rng = rng
          @rgame_change_interval = change_interval
          @rgame_idle_chance = idle_chance
          @rgame_timer = 0.0
        end

        def _attach
          @rgame_body = require_sibling(CharacterBody)
        end

        def _update(dt)
          blocked = intending_to_move? && @rgame_body.stopped?
          @rgame_timer -= dt
          reroll if blocked || @rgame_timer <= 0.0
        end

        private

        def intending_to_move? = !@rgame_body.move_x.zero? || !@rgame_body.move_y.zero?

        def reroll
          if @rgame_rng.rand < @rgame_idle_chance
            @rgame_body.set_intent(0.0, 0.0)
          else
            dx, dy = DIRECTIONS.sample(random: @rgame_rng)
            @rgame_body.set_intent(dx.to_f, dy.to_f)
          end
          @rgame_timer = @rgame_rng.rand(@rgame_change_interval)
        end
      end
    end
  end
end
