# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # Queues the node for removal once it has fully left the world bounds (plus
      # margin). From Body#offscreen?. Used by short-lived projectiles; removal is
      # deferred via queue_free so it is safe to trigger from inside the update
      # traversal.
      #
      # Bounds resolve the same way ScreenWrap's do: from the scene's world system,
      # at attach time, with `width:`/`height:` as an override.
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
          @width, @height = WorldBounds.resolve(node, @given_width, @given_height)
        end

        def update(_dt)
          x = node.x
          y = node.y
          offscreen = x < -@margin || x > @width + @margin || y < -@margin || y > @height + @margin
          node.queue_free if offscreen
        end
      end
    end
  end
end
