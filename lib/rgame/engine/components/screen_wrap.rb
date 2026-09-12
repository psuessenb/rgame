# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # Wraps the node's position toroidally within the world bounds (plus margin), so
      # an entity leaving one edge reappears on the opposite one.
      #
      # The bounds come from the scene's world system — anything answering the
      # WorldBounds contract, so Components::World or Components::TileWorld — and are
      # resolved when the node enters the tree. Passing `width:`/`height:` overrides
      # that for a node whose wrap region is not the whole world.
      #
      # The node is tested and placed in **world space**, which is the frame WorldBounds
      # is stated in: a node under an offset container wraps at the world's edge, not at
      # an edge shifted by wherever the container sits. The write goes through
      # Node2D#world_x=, so the node's local position is what actually changes.
      #
      # A wrap is a placement, not a step: it does not ask a sibling Mover's `blocked_by`
      # whether the far edge is free, so a node wrapped onto a blocker is left pressed
      # against it.
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
          x = node.world_x
          node.world_x = @width + @margin if x < -@margin
          node.world_x = -@margin if x > @width + @margin

          y = node.world_y
          node.world_y = @height + @margin if y < -@margin
          node.world_y = -@margin if y > @height + @margin
        end
      end
    end
  end
end
