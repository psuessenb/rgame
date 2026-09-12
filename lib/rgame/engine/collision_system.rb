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
    # Engine::TileBlockers is the one there is today — it divides by the tile size and
    # snaps flush against a solid tile — and a source over moving actors would query a
    # broadphase instead. Neither needs to know the other exists, because this system
    # takes the **most restrictive** answer on each axis: a box hemmed in by a wall on
    # one side and something else nearer stops at whichever is nearer.
    #
    # Holding the sources here rather than inside any one of them is what puts the
    # axis-separated order — resolve X, then resolve Y fed the resolved X — in exactly
    # one place. That order is what produces wall-sliding (a diagonal push into a wall
    # keeps the component that is still free), so every source shares one feel rather
    # than each implementing it.
    class CollisionSystem
      def initialize(world_width:, world_height:, blockers: [])
        # Array() so a lone source reads as `blockers: tiles`. Built once at
        # construction; a frame only indexes it.
        @blockers = Array(blockers)
        @world_width = world_width
        @world_height = world_height
      end

      # Move `actor` by (dx, dy), writing the resolved position back to it.
      def move(actor, dx, dy)
        box = actor.collision_box
        # Read the box AABB into locals directly rather than via box.aabb, which would
        # allocate an Array on this per-frame path.
        bx = actor.x + box.offset_x
        by = actor.y + box.offset_y
        bw = box.width
        bh = box.height

        bx = resolve_x(bx, by, bw, bh, dx)
        by = resolve_y(bx, by, bw, bh, dy)

        # Clamp the box inside the world. Floor each upper bound at 0 without a [span, 0]
        # array (this runs per actor per frame).
        max_x = @world_width - bw
        max_x = 0 if max_x.negative?
        max_y = @world_height - bh
        max_y = 0 if max_y.negative?
        bx = bx.clamp(0.0, max_x.to_f)
        by = by.clamp(0.0, max_y.to_f)

        actor.x = bx - box.offset_x
        actor.y = by - box.offset_y
      end

      # Where the box's left edge lands moving dx, against every source at once. The most
      # restrictive answer is the *smallest* landing for a rightward step and the largest
      # for a leftward one; with no sources at all the box simply moves.
      #
      # A plain index loop rather than @blockers.map/min: this runs per actor per axis per
      # frame, and both the block and the intermediate array would allocate.
      def resolve_x(x, y, w, h, dx)
        nx = x + dx
        return nx if dx.zero?

        i = 0
        while i < @blockers.size
          landed = @blockers[i].resolve_x(x, y, w, h, dx)
          nx = landed if dx.positive? ? landed < nx : landed > nx
          i += 1
        end
        nx
      end

      def resolve_y(x, y, w, h, dy)
        ny = y + dy
        return ny if dy.zero?

        i = 0
        while i < @blockers.size
          landed = @blockers[i].resolve_y(x, y, w, h, dy)
          ny = landed if dy.positive? ? landed < ny : landed > ny
          i += 1
        end
        ny
      end
    end
  end
end
