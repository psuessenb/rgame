# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # Queues the node for removal once its origin is further than `margin` past an
      # edge of the world bounds. Used by short-lived projectiles; removal is deferred
      # via queue_free so it is safe to trigger from inside the update traversal.
      #
      # The margin is what stands in for the node's size: a node drawn centred on its
      # origin has fully left once the margin is at least its half-extent.
      #
      # Bounds resolve the same way ScreenWrap's do: from the scene's world system,
      # at attach time, with `width:`/`height:` as an override. And like ScreenWrap it
      # tests the node's **world** position, so a projectile spawned as the child of an
      # offset emitter leaves at the world's edge rather than at one shifted by the
      # emitter.
      class DespawnOffscreen < Engine::Component
        def initialize(width: nil, height: nil, margin: 0.0)
          super()
          @rgame_given_width = width
          @rgame_given_height = height
          @rgame_margin = margin
          @rgame_left = @rgame_top = -margin
        end

        # See ScreenWrap#_attach: resolved per entry, so a recycled node is correct
        # after a scene change.
        def _attach
          WorldBounds.one_response!(node)
          @rgame_right = WorldBounds.resolve_width(node, @rgame_given_width) + @rgame_margin
          @rgame_bottom = WorldBounds.resolve_height(node, @rgame_given_height) + @rgame_margin
        end

        def _update(_dt)
          x = node.world_x
          y = node.world_y
          node.queue_free if x < @rgame_left || x > @rgame_right || y < @rgame_top || y > @rgame_bottom
        end
      end
    end
  end
end
