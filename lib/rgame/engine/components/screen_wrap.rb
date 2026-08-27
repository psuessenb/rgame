# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # Wraps the node's position toroidally within the world bounds (plus margin), so
      # an entity leaving one edge reappears on the opposite one. From Body#wrap!.
      #
      # The bounds come from the scene's world system — anything answering the
      # WorldBounds contract, so Components::World or Components::TileWorld — and are
      # resolved when the node enters the tree. Passing `width:`/`height:` overrides
      # that for a node whose wrap region is not the whole world.
      class ScreenWrap < Engine::Component
        def initialize(width: nil, height: nil, margin: 0.0)
          super()
          @given_width = width
          @given_height = height
          @margin = margin
        end

        # Re-resolved on every entry rather than cached from the first, so a pooled
        # entity recycled into a differently sized scene wraps against that scene.
        def on_attach
          @width, @height = WorldBounds.resolve(node, @given_width, @given_height)
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
