# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # A simple AI driver for a CharacterBody sibling: every so often it rolls a new
      # direction (one of eight, or idle) and holds it until a timer elapses — or until a
      # wall blocks it, at which point it re-rolls early instead of pushing into the wall.
      #
      # It rolls in `_control`, where a PlayerController sets a body's intent, and counts
      # the timer down in `_update`. Every `_control` in the tree runs before any
      # `_update`, so the body steps along a new heading on the tick it is rolled,
      # whichever of the two was added first. A node nothing controls rolls nothing: under
      # a SceneStack's reveal, a wanderer keeps the heading it has, and one that just
      # arrived stands still.
      #
      # It rolls with the root's RandomSource, found when it attaches, so a seeded
      # game wanders the same way every run. An `rng:` passed in wins, as a spec
      # does to pin one walker's rolls; it is anything answering `rand` as
      # `Random#rand` does.
      #
      # "Blocked" is the body's Mover#stopped?: its last step was cut short, on either
      # axis, while it meant to move. So a body declaring no `blocked_by:` is never
      # blocked, and one riding a Components::Platform re-rolls at the platform's edge
      # although the platform carries it every tick. The `_control` after a stopped step
      # rolls again, and that tick's step takes the new heading.
      class WanderController < Engine::Component
        DIRECTIONS = [
          [-1, 0], [1, 0], [0, -1], [0, 1],
          [-1, -1], [1, -1], [-1, 1], [1, 1]
        ].freeze

        def initialize(rng: nil, change_interval: 1.0..3.0, idle_chance: 0.25)
          super()
          @rgame_given_rng = rng
          @rgame_change_interval = change_interval
          @rgame_idle_chance = idle_chance
          @rgame_timer = 0.0
        end

        def _attach
          @rgame_body = require_sibling(CharacterBody)
          @rgame_rng = @rgame_given_rng || node.system!(RandomSource)
        end

        def _control(_actions)
          reroll if blocked? || @rgame_timer <= 0.0
        end

        def _update(dt)
          @rgame_timer -= dt
        end

        private

        def blocked? = intending_to_move? && @rgame_body.stopped?

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
