# frozen_string_literal: true

module RGame
  module Engine
    # The actor-facing collision system: moves any actor by a delta, resolving its
    # *collision box* (not its sprite) against every blocker source it holds, then
    # clamping the box inside the world as a backstop. Reusable by the player and
    # any NPC.
    #
    # ## What a blocker source is
    #
    # A blocker source answers one question, on one axis, over plain numbers:
    #
    #   source.resolve_x(x, y, w, h, dx) # -> where the box's left edge lands moving dx
    #   source.resolve_y(x, y, w, h, dy) # -> where the box's top  edge lands moving dy
    #
    # Engine::TileBlockers divides by the tile size and snaps flush against a solid tile;
    # Engine::ActorBlockers queries a broadphase and snaps flush against another
    # collider's edge. Neither needs to know the other exists, because this system takes
    # the **most restrictive** answer on each axis: a box hemmed in by a wall on one side
    # and something else nearer stops at whichever is nearer.
    #
    # Two more questions a source answers, and both are asked here so that no caller has
    # anything to remember:
    #
    #   source.blocker  # -> what produced the edge the last resolve returned, or nil
    #   source.moved(actor, from_x, from_y, w, h)  # -> the step has been written back
    #
    # `blocker` is how #blocked_x / #blocked_y name what stopped a step; `moved` is how a
    # source over a moving index re-buckets the mover, with the box the step started from.
    #
    # Holding the sources here rather than inside any one of them is what puts the
    # axis-separated order — resolve X, then resolve Y fed the resolved X — in exactly
    # one place. That order is what produces wall-sliding (a diagonal push into a wall
    # keeps the component that is still free), so every source shares one feel rather
    # than each implementing it.
    class CollisionSystem
      # What stopped the last #move on each axis, or nil when that axis was free. Whatever
      # a source reports, so a handler reads `blocked_x.layer` without asking which kind
      # of thing it was. Set by every #move, so read it straight after one.
      attr_reader :blocked_x, :blocked_y

      # `world_width`/`world_height` are optional because a body blocked only by other
      # actors may be in a scene with no world bounds at all.
      def initialize(world_width: nil, world_height: nil, blockers: [])
        # Array() so a lone source reads as `blockers: tiles`. Built once at
        # construction; a frame only indexes it.
        @blockers = Array(blockers)
        @world_width = world_width
        @world_height = world_height
        @blocked_x = nil
        @blocked_y = nil
      end

      # Move `actor` by (dx, dy), writing the resolved position back to it.
      def move(actor, dx, dy)
        box = actor.collision_box
        # Read the box AABB into locals directly rather than via box.aabb, which would
        # allocate an Array on this per-frame path.
        from_x = actor.x + box.offset_x
        from_y = actor.y + box.offset_y
        bw = box.width
        bh = box.height

        bx = resolve_x(from_x, from_y, bw, bh, dx)
        by = resolve_y(bx, from_y, bw, bh, dy)

        # Clamp the box inside the world, when the scene said how big it is. Floor each
        # upper bound at 0 without a [span, 0] array (this runs per actor per frame).
        if @world_width
          max_x = @world_width - bw
          max_x = 0 if max_x.negative?
          bx = bx.clamp(0.0, max_x.to_f)
        end
        if @world_height
          max_y = @world_height - bh
          max_y = 0 if max_y.negative?
          by = by.clamp(0.0, max_y.to_f)
        end

        actor.x = bx - box.offset_x
        actor.y = by - box.offset_y

        # Every source is told, with the box the step *started* from — which is what lets
        # one over a moving index re-bucket the mover without anything having stored a box
        # on its behalf.
        i = 0
        while i < @blockers.size
          @blockers[i].moved(actor, from_x, from_y, bw, bh)
          i += 1
        end
      end

      # Where the box's left edge lands moving dx, against every source at once. The most
      # restrictive answer is the *smallest* landing for a rightward step and the largest
      # for a leftward one; with no sources at all the box simply moves.
      #
      # A plain index loop rather than @blockers.map/min: this runs per actor per axis per
      # frame, and both the block and the intermediate array would allocate.
      def resolve_x(x, y, w, h, dx)
        @blocked_x = nil
        nx = x + dx
        return nx if dx.zero?

        winner = nil
        i = 0
        while i < @blockers.size
          source = @blockers[i]
          landed = source.resolve_x(x, y, w, h, dx)
          if dx.positive? ? landed < nx : landed > nx
            nx = landed
            winner = source
          end
          i += 1
        end
        # Asked here rather than lazily from the reader, because a source's own answer is
        # per axis: resolve_y runs next and overwrites it.
        @blocked_x = winner&.blocker
        nx
      end

      def resolve_y(x, y, w, h, dy)
        @blocked_y = nil
        ny = y + dy
        return ny if dy.zero?

        winner = nil
        i = 0
        while i < @blockers.size
          source = @blockers[i]
          landed = source.resolve_y(x, y, w, h, dy)
          if dy.positive? ? landed < ny : landed > ny
            ny = landed
            winner = source
          end
          i += 1
        end
        @blocked_y = winner&.blocker
        ny
      end
    end
  end
end
