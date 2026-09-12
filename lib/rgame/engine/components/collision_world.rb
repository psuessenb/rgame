# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # Scene-scoped broadphase collision system: a Component that lives on the scene
      # node (so it is born and torn down with the scene, and rides the normal update
      # traversal). Colliders register/unregister with it via their tree lifecycle;
      # each update it buckets them in a SpatialHash and reports every overlapping
      # pair. It is layer-agnostic — it reports contacts and lets the colliders'
      # owners decide meaning. See docs/api/systems.md.
      #
      # **A contact is reported as two edges, not as a state.** `on_hit` fires on the
      # step a pair starts overlapping and `on_separated` on the step it stops, each
      # once, on both colliders. Nothing fires in between, so a handler is free to
      # count, to play a sound, or to do anything else that must happen once — which
      # is the whole reason the world keeps a ContactSet per collider rather than
      # simply forwarding what the broadphase found.
      #
      # It is also *shape*-agnostic, which is what lets CircleCollider and BoxCollider
      # share it (and collide with each other). A collider is anything answering:
      #
      #   aabb_x, aabb_y, aabb_w, aabb_h  its world-space bounding box, for bucketing
      #   cx, cy                          its centre, for the range queries below
      #   overlap?(other)                 the narrowphase, which the two colliders
      #                                   settle between themselves by double dispatch
      #   layer, node                     the tag and the owner
      #   contacts                        an Engine::ContactSet, which this drives
      #   emit_hit(other)                 the contact's two edges
      #   emit_separated(other)
      #
      # None of those may allocate: they run per collider per frame.
      class CollisionWorld < Engine::Component
        def initialize(cell_size:)
          super()
          @hash = Engine::SpatialHash.new(cell_size: cell_size)
          @colliders = []
        end

        # Reset rather than merely add: the collider may be a pooled one coming back
        # from the dead, still carrying the contacts it held when it was freed.
        def register(collider)
          collider.contacts.reset
          @colliders << collider
        end

        # The partners of a collider that leaves are told on their next step, by the
        # ordinary separation pass — it is gone from the index, so the pair no longer
        # overlaps. Nothing has to be emitted here.
        def unregister(collider) = @colliders.delete(collider)

        # Yield every registered collider whose centre lies within `r` of (x, y), using
        # the spatial index built by the most recent #update. The narrowphase is a
        # centre-distance test — the query is a point + range (a turret's range ring), so
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

        # Yield every registered collider bucketed in a cell the region covers, skipping
        # those whose node is queued for removal. The rectangular counterpart to
        # #query_circle, and what a blocker source asks when it resolves a step: "what is
        # near this box".
        #
        # It inherits #query_circle's dedup contract — a collider spanning several cells
        # may be yielded more than once — so a caller that *selects* is written
        # dup-insensitively, the way #nearest and Engine::ActorBlockers both are. Unlike
        # #query_circle there is no narrowphase here at all: the bucket walk is the whole
        # answer, and refining it is the caller's business. Layer-agnostic; filter by
        # `collider.layer` in the block. Allocation-free.
        def query_box(x, y, w, h)
          @hash.query(x, y, w, h) do |collider|
            next if collider.node.freed?

            yield collider
          end
        end

        # Re-bucket a collider that has moved since #update built the index, so a query
        # later in the same step still finds it where it now is. `from_*` is the box it
        # was bucketed at — the caller knows it, which is what lets the index keep no
        # per-item state of its own.
        #
        # This is what makes a mid-step query exact rather than nearly right. Buckets are
        # filled once per step and a collider that moves afterwards is still bucketed
        # where it was, so a query over cells it has left does not reach it. Measured over
        # 60,000 queries at two hundred actors: 116 misses left stale, 0 re-indexed, and
        # padding the query instead is not exact at any pad — it compensates for the
        # *other* actor's staleness by inflating the *mover's* step. Engine::CollisionSystem
        # calls this through a blocker source's #moved, so nothing a game writes has to
        # remember it; anything else that moves a collider mid-step may call it directly.
        #
        # Allocation-free, so a resolver may call it every step.
        def reindex(collider, from_x, from_y, from_w, from_h)
          @hash.remove(collider, from_x, from_y, from_w, from_h)
          insert(collider)
        end

        # The registered collider nearest to (x, y) within range `r`, or nil when none
        # qualifies. Restrict to a single `layer:` (the common case: a turret targeting only
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

        # Is the cell containing the *world* point (x, y) free — "may a pickup spawn on
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

        # Rebuild the index, then report the step's two kinds of edge. Starting edges
        # come first and every one of them for the step is emitted before the first
        # ending one, because a separation is only knowable once every pair has been
        # looked at.
        def update(_dt)
          @hash.clear
          @colliders.each do |collider|
            collider.contacts.begin_frame
            insert(collider)
          end

          report_contacts
          report_separations
        end

        private

        def insert(collider)
          @hash.insert(collider, collider.aabb_x, collider.aabb_y, collider.aabb_w, collider.aabb_h)
        end

        # Find this step's overlapping pairs, record them, and fire on_hit for the ones
        # that were not overlapping last step.
        def report_contacts
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

            pair_up(a)
          end
        end

        def pair_up(a)
          contacts = a.contacts
          @hash.query(a.aabb_x, a.aabb_y, a.aabb_w, a.aabb_h) do |b|
            # object_id ordering visits each unordered pair once (and skips self);
            # the freed? guards skip nodes already queued for removal, so a dead
            # entity stops colliding — and its partners are told it is gone, by the
            # separation pass finding the pair missing from this step.
            next if a.node.freed? || b.node.freed? || a.object_id >= b.object_id
            # The broadphase offers a pair once per cell the two share, so a pair
            # sharing two cells arrives here twice. This is where the repeat stops,
            # which is what makes the edge below per pair rather than per cell.
            next if contacts.touching?(b)
            next unless a.overlap?(b)

            # Asked before recording, and of one side only: the two lists are filled
            # in lockstep, so b would give the same answer about a.
            started = contacts.started?(b)
            contacts.add(b)
            b.contacts.add(a)
            next unless started

            a.emit_hit(b)
            b.emit_hit(a)
          end
        end

        # Fire on_separated for every pair that was in contact last step and is not in
        # contact now — including the pairs that ended because one side was destroyed
        # or left the tree, which is exactly the case a game would otherwise have to
        # notice for itself. A collider whose own node is queued for removal is skipped,
        # the same rule everything else here follows.
        def report_separations
          count = @colliders.size
          i = 0
          while i < count
            collider = @colliders[i]
            i += 1
            next if collider.node.freed?

            collider.contacts.each_ended { |other| collider.emit_separated(other) }
          end
        end
      end
    end
  end
end
