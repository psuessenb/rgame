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
          @rgame_given_width = width
          @rgame_given_height = height
          @rgame_margin = margin
          @rgame_left = @rgame_top = -margin
        end

        # Re-resolved on every entry rather than cached from the first, so a pooled
        # entity recycled into a differently sized scene wraps against that scene.
        def _attach
          WorldBounds.one_response!(node)
          @rgame_right = WorldBounds.resolve_width(node, @rgame_given_width) + @rgame_margin
          @rgame_bottom = WorldBounds.resolve_height(node, @rgame_given_height) + @rgame_margin
        end

        def _update(_dt)
          x = node.world_x
          node.world_x = @rgame_right if x < @rgame_left
          node.world_x = @rgame_left if x > @rgame_right

          y = node.world_y
          node.world_y = @rgame_bottom if y < @rgame_top
          node.world_y = @rgame_top if y > @rgame_bottom
        end
      end
    end
  end
end
