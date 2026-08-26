# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # A simple AI driver for a CharacterBody sibling: every so often it rolls a new
      # direction (one of eight, or idle) and holds it until a timer elapses — or until a
      # wall blocks it, at which point it re-rolls early instead of pushing into the wall.
      # The RNG is injected so behaviour is deterministic in tests.
      #
      # "Blocked" is measured as *the node did not move while intending to*, not asked of
      # a collision world — so this works over any CharacterBody, and simply never fires
      # for one whose steps always land.
      class WanderController < Engine::Component
        MOVED_EPS = 1e-6
        DIRECTIONS = [
          [-1, 0], [1, 0], [0, -1], [0, 1],
          [-1, -1], [1, -1], [-1, 1], [1, 1]
        ].freeze

        def initialize(rng: Random.new, change_interval: 1.0..3.0, idle_chance: 0.25)
          super()
          @rng = rng
          @change_interval = change_interval
          @idle_chance = idle_chance
          @timer = 0.0 # rolls a direction on the first update
        end

        def on_attach
          @body = node.get_component(CharacterBody)
          @last_x = node.x
          @last_y = node.y
        end

        def update(dt)
          blocked = intending_to_move? && !moved_since_last?
          @last_x = node.x
          @last_y = node.y

          @timer -= dt
          reroll if blocked || @timer <= 0.0
        end

        private

        def intending_to_move? = !@body.move_x.zero? || !@body.move_y.zero?

        def moved_since_last?
          (node.x - @last_x).abs > MOVED_EPS || (node.y - @last_y).abs > MOVED_EPS
        end

        def reroll
          if @rng.rand < @idle_chance
            @body.set_intent(0.0, 0.0)
          else
            dx, dy = DIRECTIONS.sample(random: @rng)
            @body.set_intent(dx.to_f, dy.to_f)
          end
          @timer = @rng.rand(@change_interval)
        end
      end
    end
  end
end
