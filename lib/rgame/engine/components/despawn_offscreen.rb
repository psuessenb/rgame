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
          @given_width = width
          @given_height = height
          @margin = margin
        end

        # See ScreenWrap#on_attach: resolved per entry, so a recycled node is correct
        # after a scene change.
        def on_attach
          WorldBounds.one_response!(node)
          @width, @height = WorldBounds.resolve(node, @given_width, @given_height)
        end

        def update(_dt)
          x = node.world_x
          y = node.world_y
          offscreen = x < -@margin || x > @width + @margin || y < -@margin || y > @height + @margin
          node.queue_free if offscreen
        end
      end
    end
  end
end
