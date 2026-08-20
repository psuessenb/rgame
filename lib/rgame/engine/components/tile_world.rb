# frozen_string_literal: true

module RGame
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
      # OVERLAY_Z. Actors draw at a z in between (the renderer sorts by z, so the
      # draw-call order doesn't matter). TileMapLayer draws both.
      #
      # **It does not draw.** Drawing the map is RGame::Engine::TileMapLayer, a
      # node that lives inside the WorldView so the map is drawn once per
      # viewport like the rest of the world. This stays a system — the thing
      # actors ask about collision and bounds — and a system that also drew was
      # always the odd part of it.
      #
      # It owns the map's **animation clock**. Nothing below reads a wall clock —
      # see CLAUDE.md, "`draw` renders state; time enters through `update`" — so the
      # elapsed seconds animated tiles run on are accumulated here and handed down at
      # draw time. Stop calling `update` and the water freezes, which is what pausing
      # should look like.
      class TileWorld < Engine::Component
        GROUND_Z  = 0
        OVERLAY_Z = 20

        attr_reader :tilemap_id, :elapsed

        # `cameras` are the cameras this map bounds — every player's, normally.
        # A camera may not show past the world's edges, and this is what knows
        # how big the world is; the cameras themselves are owned by players.
        def initialize(map:, tilemap_id:, cameras: [])
          super()
          @map = map
          @tilemap_id = tilemap_id
          @elapsed = 0.0
          Array(cameras).each { |camera| bound(camera) }
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

        # Clamp a camera to this map's edges. Called for each camera the scene
        # hands over, and again for one that arrives later (a player joining).
        def bound(camera)
          camera.world_width = @map.pixel_width
          camera.world_height = @map.pixel_height
          camera
        end

        # Move an actor (responds to x/y/collision_box) by (dx, dy), sliding along solids
        # and clamped inside the world. Delegates to the reused collision system.
        def move(actor, dx, dy) = @collision.move(actor, dx, dy)

        def solid?(col, row) = @map.solid_tile?(col, row)

        # Advances the tile animations. Seconds, like every other duration here.
        def update(dt)
          @elapsed += dt
        end
      end
    end
  end
end
