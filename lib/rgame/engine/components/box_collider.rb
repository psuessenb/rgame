# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # A rectangular collision shape on a node — the sibling of CircleCollider for
      # entities that are honestly box-shaped (a snake segment, a crate, a platform).
      # It registers itself with the scene's CollisionWorld when it enters the tree
      # and unregisters on leaving, so a spawned/despawned entity can't leak a
      # registration.
      #
      # The rectangle is an Engine::CollisionBox: an offset + size relative to the
      # node's origin, so a 32x32 sprite can carry a small box at its feet the same
      # way a TileCharacterBody does. The `layer` is an opaque tag the game reads in
      # its on_hit handler to decide what a contact means. See docs/api/systems.md.
      #
      # The box stays axis-aligned in world space: it does not rotate with the node.
      # That is what an AABB buys — a spinning entity wants a CircleCollider, which
      # is rotation-invariant, rather than a per-frame box recompute.
      class BoxCollider < Engine::Component
        # Fired by CollisionWorld for each overlapping collider; the listener gets the
        # other collider and reads its #layer / #node to react.
        signal :on_hit, Engine::Signal.define(:other)

        # box is writable so a pooled entity can retune its shape on reset — assign any
        # CollisionBox, CollisionBox.bottom_anchored(...) included. CollisionWorld reads
        # it fresh each frame, so no re-registration.
        attr_accessor :box
        attr_reader :layer

        def initialize(width:, height:, offset_x: 0, offset_y: 0, layer: :default)
          super()
          @box = Engine::CollisionBox.new(width:, height:, offset_x:, offset_y:)
          @layer = layer
        end

        def on_attach = node.system(CollisionWorld).register(self)
        def on_detach = node.system(CollisionWorld)&.unregister(self)

        # The broadphase AABB in world space, one component per call rather than
        # CollisionBox#aabb's Array: CollisionWorld reads these for every collider
        # every frame, and that path may not allocate.
        def aabb_x = node.world_x + @box.offset_x
        def aabb_y = node.world_y + @box.offset_y
        def aabb_w = @box.width
        def aabb_h = @box.height

        # World-space centre of the box — what CollisionWorld's range queries measure
        # from, so a box collider is targetable on the same terms as a circle. Note it
        # is the box's centre, not the node's origin, which is where a circle's is.
        def cx = aabb_x + (@box.width / 2.0)
        def cy = aabb_y + (@box.height / 2.0)

        # Narrowphase, first half of the double dispatch: hand this shape's numbers to
        # the *other* collider and let it pick the test, so neither side has to ask what
        # kind the other is. CircleCollider#overlap? is the mirror image.
        def overlap?(other) = other.overlap_box?(aabb_x, aabb_y, aabb_w, aabb_h)

        # Second half: the two tests another collider dispatches into.
        def overlap_box?(x, y, w, h)
          Engine::CollisionBox.overlap?(aabb_x, aabb_y, aabb_w, aabb_h, x, y, w, h)
        end

        def overlap_circle?(x, y, r)
          Engine::CollisionBox.overlap_circle?(aabb_x, aabb_y, aabb_w, aabb_h, x, y, r)
        end

        # Called by CollisionWorld on contact (the signal's emit is otherwise private).
        def emit_hit(other) = on_hit_signal.emit(other)
      end
    end
  end
end
