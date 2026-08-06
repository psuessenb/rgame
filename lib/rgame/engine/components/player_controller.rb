# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # Drives a CharacterBody sibling from two input axes — direct 8-way walking, no
      # inertia (unlike ThrustController). Each frame it copies the axis snapshot into
      # the body's movement intent; the body does the collision-checked move.
      class PlayerController < Engine::Component
        def initialize(x_axis: :move_x, y_axis: :move_y)
          super()
          @x_axis = x_axis
          @y_axis = y_axis
        end

        def on_attach = @body = node.get_component(CharacterBody)

        def control(actions)
          @body.set_intent(actions.axis(@x_axis), actions.axis(@y_axis))
        end
      end
    end
  end
end
