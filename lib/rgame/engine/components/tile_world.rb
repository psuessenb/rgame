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
      # draw-call order doesn't matter). The camera is centred by the scene before any
      # drawing.
      #
      # The camera it draws through belongs to a player, not to this component or
      # to the scene — see RGame::Engine::Player. It also sets that camera's world
      # bounds to the map's, since the map is what the camera may not show past
      # and this is what knows how big it is.
      #
      # It also owns the map's **animation clock**. Nothing below reads a wall clock —
      # see CLAUDE.md, "`draw` renders state; time enters through `update`" — so the
      # elapsed seconds animated tiles run on are accumulated here and handed down at
      # draw time. Stop calling `update` and the water freezes, which is what pausing
      # should look like.
      class TileWorld < Engine::Component
        GROUND_Z  = 0
        OVERLAY_Z = 20

        def initialize(map:, tilemap_id:, camera:)
          super()
          @map = map
          @tilemap_id = tilemap_id
          @camera = camera
          @camera.world_width = map.pixel_width
          @camera.world_height = map.pixel_height
          @elapsed = 0.0
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

        # Advances the tile animations. Seconds, like every other duration here.
        def update(dt)
          @elapsed += dt
        end

        # The map is culled to what the camera can see, so this needs the size of
        # the view as well as its offset. A camera no longer carries one — it is
        # drawn through as many viewports as there are players — so the size comes
        # from the platform for now, and will come from the view being drawn once
        # there is more than one.
        def draw(renderer)
          view_width = context.width
          view_height = context.height
          renderer.tilemap(@tilemap_id, @camera.x, @camera.y,
                           view_width, view_height, elapsed: @elapsed)
          renderer.tilemap_overlay(@tilemap_id, @camera.x, @camera.y,
                                   view_width, view_height,
                                   z: OVERLAY_Z, elapsed: @elapsed)
        end
      end
    end
  end
end
