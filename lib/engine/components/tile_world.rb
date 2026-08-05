# frozen_string_literal: true

module Engine
  module Components
    # The scene-scoped tile world: a system component (it lives on the scene node and
    # is found with node.system(TileWorld)) that owns the parsed Engine::TileMap and
    # everything an actor needs from it — collision against the solid tiles, the world
    # bounds, and drawing the map through the scene's camera.
    #
    # Collision reuses Engine::CollisionSystem (TileCollision + a world-bounds clamp);
    # the tile solidity is whatever the map's tileset reports (baked per-tile in Tiled).
    #
    # Drawing splits into two z bands so actors can sit between them: the below band
    # (ground, same-level detail) at GROUND_Z and the above band (canopies, roofs) at
    # OVERLAY_Z. Actors draw at a z in between (Gosu sorts by z, so the draw-call order
    # doesn't matter). The camera is centred by the scene before any drawing.
    class TileWorld < Engine::Component
      GROUND_Z  = 0
      OVERLAY_Z = 20

      def initialize(map:, tilemap_id:, camera:)
        super()
        @map = map
        @tilemap_id = tilemap_id
        @camera = camera
        @collision = Engine::CollisionSystem.new(
          tile_collision: Engine::TileCollision.new(
            tile_width: map.tile_width, tile_height: map.tile_height,
            solid: ->(col, row) { map.solid_tile?(col, row) }
          ),
          world_width: map.pixel_width, world_height: map.pixel_height
        )
      end

      def world_width = @map.pixel_width
      def world_height = @map.pixel_height

      # Move an actor (responds to x/y/collision_box) by (dx, dy), sliding along solids
      # and clamped inside the world. Delegates to the reused collision system.
      def move(actor, dx, dy) = @collision.move(actor, dx, dy)

      def solid?(col, row) = @map.solid_tile?(col, row)

      def draw(renderer)
        renderer.tilemap(@tilemap_id, @camera.x, @camera.y,
                         @camera.viewport_width, @camera.viewport_height)
        renderer.tilemap_overlay(@tilemap_id, @camera.x, @camera.y,
                                 @camera.viewport_width, @camera.viewport_height, z: OVERLAY_Z)
      end
    end
  end
end
