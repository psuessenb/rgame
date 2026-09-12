# frozen_string_literal: true

module RGame
  module Engine
    # The registered colliders as a blocker source: the broadphase answers "what is near
    # this box", and the same snapping arithmetic TileBlockers runs against a tile edge
    # runs against a collider's edge instead. Pure — it needs no scene, no node and no
    # tree, only something answering `query_box` and `reindex`.
    #
    # It answers the blocker-source question — "where does this box land moving dx" — that
    # Engine::CollisionSystem asks of every source it holds; see that class's header for
    # the protocol and for how the most restrictive answer wins across sources. This is
    # the source that makes two actors stop each other the way a wall stops one.
    #
    # ## Per body, unlike the other sources
    #
    # A TileBlockers is the same grid for everybody, so one is shared by every actor on
    # the map. This one takes an `owner` and a layer list, so it belongs to exactly one
    # body: two actors declaring different `blocked_by` cannot share one. That is why
    # Components::Mover builds its own resolver rather than borrowing the scene's.
    #
    # ## Three things a grid does not need
    #
    # - **The most restrictive candidate wins.** Several colliders may be in the way, so
    #   this keeps a running minimum (maximum, going the other way). That is
    #   dup-insensitive, which matters because the broadphase may offer the same collider
    #   once per cell the two share.
    # - **An overlap that already exists is not resolved.** A step is blocked only if it
    #   *crosses* an edge the mover was on the near side of. Two actors that start
    #   overlapping stay overlapping and neither is teleported out — blocking stops the
    #   mover, it never moves the thing it hit.
    # - **Boxes only.** A CircleCollider on a blocked layer is skipped, and still reports
    #   on_hit exactly as it does now. It is a documented limit rather than a raise at
    #   attach: layer membership is a runtime fact, so a check at attach would catch only
    #   the circles that already exist and quietly miss the ones spawned later.
    class ActorBlockers
      # `world` answers query_box/reindex (a Components::CollisionWorld); `owner` is the
      # mover's own collider, excluded by identity so a body is never stopped by itself;
      # `layers` is the set of collider layers that may stop it.
      def initialize(world:, owner:, layers:)
        @world = world
        @owner = owner
        @layers = Array(layers)
        @blocker = nil
      end

      # Who produced the edge the last resolve_x / resolve_y returned, or nil when that
      # axis was free. Per-move state, and safe because this source belongs to one body,
      # which reads it inside its own update.
      attr_reader :blocker

      # Where the box's left edge lands moving dx, snapping flush against the nearest
      # collider it would cross into.
      def resolve_x(x, y, w, h, dx)
        @blocker = nil
        nx = x + dx
        return nx if dx.zero?

        # The swept box: everything the step passes through, which is what has to be
        # asked about rather than just where the box is now.
        sweep_x = dx.negative? ? nx : x
        @best = nx
        @world.query_box(sweep_x, y, w + dx.abs, h) do |other|
          next unless candidate?(other)
          # The far axis has to overlap for the near one to be blocked at all: a collider
          # the box passes above or below is not in the way. Half-open on both edges, like
          # CollisionBox.overlap?, so boxes that merely touch are not overlapping.
          next unless y < other.aabb_y + other.aabb_h && other.aabb_y < y + h

          if dx.positive?
            edge = other.aabb_x
            take_min(edge - w, other) if x + w <= edge && nx + w > edge
          else
            edge = other.aabb_x + other.aabb_w
            take_max(edge, other) if x >= edge && nx < edge
          end
        end
        @best
      end

      # The mirror of resolve_x. CollisionSystem feeds it the resolved x, which is what
      # makes a diagonal push into a wall slide along it.
      def resolve_y(x, y, w, h, dy)
        @blocker = nil
        ny = y + dy
        return ny if dy.zero?

        sweep_y = dy.negative? ? ny : y
        @best = ny
        @world.query_box(x, sweep_y, w, h + dy.abs) do |other|
          next unless candidate?(other)
          next unless x < other.aabb_x + other.aabb_w && other.aabb_x < x + w

          if dy.positive?
            edge = other.aabb_y
            take_min(edge - h, other) if y + h <= edge && ny + h > edge
          else
            edge = other.aabb_y + other.aabb_h
            take_max(edge, other) if y >= edge && ny < edge
          end
        end
        @best
      end

      # Called by CollisionSystem#move once the resolved position is written back, with
      # the box the step started from. Re-bucketing the owner here is what keeps the index
      # exact for whoever resolves next this step; see CollisionWorld#reindex.
      def moved(_actor, from_x, from_y, from_w, from_h)
        @world.reindex(@owner, from_x, from_y, from_w, from_h)
      end

      private

      # The running minimum for a step going right or down, and the maximum for one going
      # left or up. `@best` starts at the unblocked landing, so a candidate further away
      # than the step reaches loses the comparison and nothing special is needed for it —
      # and the strict `<` is what makes the same collider offered twice by the broadphase
      # give the same answer as once.
      def take_min(landed, other)
        return unless landed < @best

        @best = landed
        @blocker = other
      end

      def take_max(landed, other)
        return unless landed > @best

        @best = landed
        @blocker = other
      end

      # A collider queued for removal is skipped here as well as by the world's own query,
      # which is deliberate duplication: what a source may be stopped by is the source's
      # rule, and a corpse blocking a step for one more frame is exactly the kind of thing
      # that would only ever be noticed as a mystery. It costs one call per candidate, and
      # a candidate list is a handful of colliders.
      def candidate?(other)
        !other.equal?(@owner) &&
          other.is_a?(Components::BoxCollider) &&
          @layers.include?(other.layer) &&
          !other.node.freed?
      end
    end
  end
end
