# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # Scene-scoped broadphase collision system: a Component that lives on the scene
      # node (so it is born and torn down with the scene, and rides the normal update
      # traversal). Colliders register/unregister with it via their tree lifecycle;
      # each update it buckets them in a SpatialHash and fires on_hit on every
      # overlapping pair. It is layer-agnostic — it reports contacts and lets the
      # colliders' owners decide meaning. See docs/api/systems.md.
      #
      # It is also *shape*-agnostic, which is what lets CircleCollider and BoxCollider
      # share it (and collide with each other). A collider is anything answering:
      #
      #   aabb_x, aabb_y, aabb_w, aabb_h  its world-space bounding box, for bucketing
      #   cx, cy                          its centre, for the range queries below
      #   overlap?(other)                 the narrowphase, which the two colliders
      #                                   settle between themselves by double dispatch
      #   layer, node, emit_hit(other)    the tag, the owner, and the contact signal
      #
      # None of those may allocate: they run per collider per frame.
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
        # the collider's own size isn't added in. Colliders whose node is queued for
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

        # Is the cell containing the *world* point (x, y) free — "may the fruit spawn on
        # this square?" A point, not a region: pass any coordinate inside the square you
        # mean. The cells are the broadphase's own, so set `cell_size` to the game's
        # square and the two grids line up.
        #
        # Two coordinate gotchas, both easy to get wrong from a node that has neither in
        # mind:
        #
        # - The index holds **world** coordinates, because that is what a collider
        #   reports. A node whose own grid starts somewhere else adds its world origin
        #   before asking (`node.world_x + col * cell_size`) — and puts that origin on a
        #   multiple of `cell_size`, since the cells are the hash's own lattice anchored
        #   at the world origin. A board off that lattice has each square straddling two
        #   cells, and both read occupied.
        # - It answers about the index the most recent #update built, exactly as
        #   #query_circle and #nearest do. Before the first update every cell is empty.
        #
        # The bucket is the answer, geometry and all: the broadphase's cell walk is
        # half-open exactly like CollisionBox.overlap?, so a collider is bucketed in a
        # cell if and only if it overlaps that cell's area. All this adds is the one
        # thing the index cannot know — that a collider queued for removal no longer
        # occupies anything, the same rule the queries above follow, so a corpse cannot
        # reserve a square.
        #
        # Allocation-free, including the miss: SpatialHash#cell_empty? is asked first
        # because it is the only way to look at a cell without materialising a bucket for
        # it, and a caller scanning a board for a free square asks mostly about empty
        # ones.
        def cell_empty?(x, y)
          return true if @hash.cell_empty?(x, y)

          # A zero-size region is the single cell containing the point. The loop runs to
          # the end of the bucket rather than stopping at the first occupant: a non-local
          # `return` out of a block allocates in CRuby (measurably — one object per call),
          # and a bucket holds a handful of items, so the flag is cheaper than the
          # short-circuit it replaces.
          free = true
          @hash.query(x, y, 0, 0) { |collider| free &&= collider.node.freed? }
          free
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

            @hash.query(a.aabb_x, a.aabb_y, a.aabb_w, a.aabb_h) do |b|
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
          @hash.insert(collider, collider.aabb_x, collider.aabb_y, collider.aabb_w, collider.aabb_h)
        end
      end
    end
  end
end
