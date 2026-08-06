# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # Scene-scoped broadphase collision system: a Component that lives on the scene
      # node (so it is born and torn down with the scene, and rides the normal update
      # traversal). CircleColliders register/unregister with it via their tree
      # lifecycle; each update it buckets them in a SpatialHash and fires on_hit on
      # every overlapping pair. It is layer-agnostic — it reports contacts and lets
      # the colliders' owners decide meaning. See docs/api/systems.md.
      class CollisionWorld < Engine::Component
        def initialize(cell_size:)
          super()
          @hash = Engine::SpatialHash.new(cell_size: cell_size)
          @colliders = []
        end

        def register(collider) = @colliders << collider
        def unregister(collider) = @colliders.delete(collider)

        # Yield every registered collider whose centre lies within `r` of (x, y), using
        # the spatial index built by the most recent #update. The narrowphase is a
        # centre-distance test — the query is a point + range (a tower's range ring), so
        # the collider's own radius isn't added in. Colliders whose node is queued for
        # removal are skipped. As with SpatialHash#query a collider spanning several cells
        # may be yielded more than once, so callers that *select* (e.g. #nearest) are
        # written dup-insensitively. Layer-agnostic — filter by `collider.layer` in the
        # block. Allocation-free.
        def query_circle(x, y, r)
          r2 = r * r
          @hash.query_circle(x, y, r) do |collider|
            next if collider.node.freed?

            dx = collider.cx - x
            dy = collider.cy - y
            yield collider if (dx * dx) + (dy * dy) <= r2
          end
        end

        # The registered collider nearest to (x, y) within range `r`, or nil when none
        # qualifies. Restrict to a single `layer:` (the common case: a tower targeting only
        # :enemy). Dup-safe — it keeps the running minimum, so #query_circle's possible
        # multi-cell repeats don't matter. Allocation-free.
        def nearest(x, y, r, layer: nil)
          best = nil
          best_d2 = nil
          query_circle(x, y, r) do |collider|
            next if layer && collider.layer != layer

            dx = collider.cx - x
            dy = collider.cy - y
            d2 = (dx * dx) + (dy * dy)
            next unless best_d2.nil? || d2 < best_d2

            best = collider
            best_d2 = d2
          end
          best
        end

        def update(_dt)
          @hash.clear
          @colliders.each { |c| insert(c) }

          # Index-bounded over the count at frame start: an on_hit handler may spawn
          # entities (a rock splitting), which `register`s new colliders mid-loop; those
          # appended ones are skipped this frame (processed next) rather than mutating
          # the array being iterated. The hash was built before the loop, so they're
          # absent from queries too — consistent.
          count = @colliders.size
          i = 0
          while i < count
            a = @colliders[i]
            i += 1
            next if a.node.freed?

            r = a.radius
            d = r * 2
            @hash.query(a.cx - r, a.cy - r, d, d) do |b|
              # object_id ordering visits each unordered pair once (and skips self);
              # the freed? guards skip nodes already queued for removal, so a dead
              # entity stops colliding and duplicate (multi-cell) yields are ignored.
              next if a.node.freed? || b.node.freed? || a.object_id >= b.object_id
              next unless a.overlap?(b)

              a.emit_hit(b)
              b.emit_hit(a)
            end
          end
        end

        private

        def insert(collider)
          r = collider.radius
          d = r * 2
          @hash.insert(collider, collider.cx - r, collider.cy - r, d, d)
        end
      end
    end
  end
end
