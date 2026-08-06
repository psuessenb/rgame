# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # Wraps the node's position toroidally within a rectangle (plus margin), so an
      # entity leaving one edge reappears on the opposite one. From Body#wrap!. The
      # bounds are passed in; in a scrolling game they'd come from a scene-scoped
      # World system instead.
      class ScreenWrap < Engine::Component
        def initialize(width:, height:, margin: 0.0)
          super()
          @width = width
          @height = height
          @margin = margin
        end

        def update(_dt)
          node.x = @width + @margin if node.x < -@margin
          node.x = -@margin if node.x > @width + @margin
          node.y = @height + @margin if node.y < -@margin
          node.y = -@margin if node.y > @height + @margin
        end
      end
    end
  end
end
