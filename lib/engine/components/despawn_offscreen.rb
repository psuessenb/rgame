# frozen_string_literal: true

module Engine
  module Components
    # Queues the node for removal once it has fully left the bounds (plus margin).
    # From Body#offscreen?. Used by short-lived projectiles; removal is deferred via
    # queue_free so it is safe to trigger from inside the update traversal.
    class DespawnOffscreen < Engine::Component
      def initialize(width:, height:, margin: 0.0)
        super()
        @width = width
        @height = height
        @margin = margin
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
