# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # Direct, per-step movement for a walking actor (player or NPC). A controller writes a
      # movement intent — each axis in -1..1 — and this component turns it into a real move
      # each update, at a fixed speed and with no inertia (unlike Velocity, which integrates
      # a velocity the controller sets, and ThrustController, which accelerates one).
      #
      # The intent doubles as the facing for AnimatedSprite (move_x / move_y readers), so
      # a character is just CharacterBody + a controller + AnimatedSprite.
      #
      # This one moves the node freely: it needs no sprite, no dimensions and no system on
      # the scene, so it suits an actor in a world with nothing to bump into.
      # TileCharacterBody is the subclass that resolves each step against the scene's solid
      # tiles instead; it overrides `apply_move` and nothing else, which is the whole seam
      # between "what the intent means" and "where the step lands".
      class CharacterBody < Engine::Component
        attr_reader :move_x, :move_y

        def initialize(speed:)
          super()
          @speed = speed
          @move_x = 0.0
          @move_y = 0.0
        end

        # Set this step's movement intent; each axis is in -1..1.
        def set_intent(intent_x, intent_y)
          @move_x = intent_x
          @move_y = intent_y
        end

        def update(dt)
          return if @move_x.zero? && @move_y.zero?

          apply_move(@move_x * @speed * dt, @move_y * @speed * dt)
        end

        # Where a step lands — the one method a collision-aware body replaces. Kept
        # separate from `update` so a subclass inherits the intent, the speed and the
        # "don't bother when standing still" check rather than restating them.
        def apply_move(dx, dy)
          node.x += dx
          node.y += dy
        end
      end
    end
  end
end
