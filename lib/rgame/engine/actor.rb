# frozen_string_literal: true

module RGame
  module Engine
    # A character in the world. Composes the pieces it owns — a collision box, an
    # animator, a sprite id (the renderer maps it to a sheet), and a controller that
    # decides movement — rather than baking them in. Pure logic; no Gosu.
    #
    # The controller responds to `intent(dt, input) -> [ix, iy]` with each axis in
    # [-1, 1]; PlayerController reads input, AI/scripted controllers ignore it.
    class Actor
      attr_accessor :x, :y
      attr_reader :sprite_id, :collision_box, :animator

      def initialize(x:, y:, sprite_id:, collision_box:, animator:, controller:, speed: 120.0)
        @x = x
        @y = y
        @sprite_id = sprite_id
        @collision_box = collision_box
        @animator = animator
        @controller = controller
        @speed = speed
      end

      def update(dt, collision_system, input)
        intent_x, intent_y = @controller.intent(dt, input)

        collision_system.move(self, intent_x * @speed * dt, intent_y * @speed * dt)

        @animator.play(walk_animation(intent_x, intent_y))
        @animator.update(dt)
      end

      # [row, col, flip_x] for the current frame.
      def frame
        @animator.frame
      end

      private

      # Facing follows movement intent (so we still "walk" while pushing a wall);
      # horizontal wins over vertical.
      def walk_animation(intent_x, intent_y)
        if    intent_x.negative? then :walk_left
        elsif intent_x.positive? then :walk_right
        elsif intent_y.negative? then :walk_up
        elsif intent_y.positive? then :walk_down
        else                          :stand
        end
      end
    end
  end
end
