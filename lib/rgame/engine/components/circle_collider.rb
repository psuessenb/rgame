# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # A circular collision shape on a node. It registers itself with the scene's
      # CollisionWorld system when it enters the tree and unregisters on leaving —
      # the engine fires both hooks, so a spawned/despawned entity can't leak a
      # registration. Its world centre is the node's world origin; the
      # `layer` is an opaque tag the game reads in its on_hit handler to decide what a
      # contact means (bullet-vs-rock, etc.). See docs/api/systems.md.
      class CircleCollider < Engine::Component
        # Fired by CollisionWorld for each overlapping collider; the listener gets the
        # other collider and reads its #layer / #node to react.
        signal :on_hit, Engine::Signal.define(:other)

        # radius is writable so a pooled entity (e.g. a multi-tier rock) can retune its
        # shape on reset; CollisionWorld reads it fresh each frame, so no re-registration.
        attr_accessor :radius
        attr_reader :layer

        def initialize(radius:, layer: :default)
          super()
          @radius = radius
          @layer = layer
        end

        def on_attach = node.system(CollisionWorld).register(self)
        def on_detach = node.system(CollisionWorld)&.unregister(self)

        # World-space centre — the node's own origin, in world coordinates.
        def cx = node.world_x
        def cy = node.world_y

        def overlap?(other)
          Engine::CircleCollider.overlap?(cx, cy, @radius, other.cx, other.cy, other.radius)
        end

        # Called by CollisionWorld on contact (the signal's emit is otherwise private).
        def emit_hit(other) = on_hit_signal.emit(other)
      end
    end
  end
end
