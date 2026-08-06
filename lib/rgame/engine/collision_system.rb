# frozen_string_literal: true

module RGame
  module Engine
    # The actor-facing collision system: moves any actor by a delta, resolving its
    # *collision box* (not its sprite) against the tiles via TileCollision, then
    # clamping the box inside the world as a backstop. Reusable by the player and
    # any NPC.
    #
    class CollisionSystem
      def initialize(tile_collision:, world_width:, world_height:)
        @tiles = tile_collision
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

        bx = @tiles.resolve_x(bx, by, bw, bh, dx)
        by = @tiles.resolve_y(bx, by, bw, bh, dy)

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
    end
  end
end
