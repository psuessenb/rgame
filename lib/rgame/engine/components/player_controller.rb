# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # Drives a CharacterBody sibling from two input axes — direct 8-way walking, no
      # inertia (unlike ThrustController). Each frame it copies the axis snapshot into
      # the body's movement intent; what the body then does with it is the body's
      # business — a plain CharacterBody moves the node, a TileCharacterBody resolves
      # the step against the map. The lookup names the base class and get_component
      # matches by ancestry, so this needs to know nothing about which is there.
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
