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
      # **It does not draw.** Drawing the map is RGame::Engine::TileMapLayer, one
      # node per Tiled layer, mounted inside the WorldView so the map is drawn
      # once per viewport like the rest of the world. This stays a system — the
      # thing actors ask about collision and bounds — and a system that also
      # drew was always the odd part of it.
      #
      # It owns the map's **animation clock**. Nothing below reads a wall clock —
      # see CLAUDE.md, "`draw` renders state; time enters through `update`" — so the
      # elapsed seconds animated tiles run on are accumulated here and handed down at
      # draw time. Stop calling `update` and the water freezes, which is what pausing
      # should look like.
      class TileWorld < Engine::Component
        # It is a WorldBounds: a scene with a tile map answers "how big is the world"
        # from the map's own pixel size, and ScreenWrap/DespawnOffscreen find it here
        # exactly as they would find a plain Components::World.
        include WorldBounds

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

        def layer_count = @map.layer_count

        # The first layer Tiled flags `above`, or the layer count if none is —
        # which is where TileMapLayer.mount leaves the gap for the actors, so a
        # map with no flag puts them over everything. Read once at mount rather
        # than per frame: which layers cover the actors is a fact about the
        # scene's arrangement, and the arrangement is made once.
        def first_above_layer
          layer_count.times.find { |index| @map.above_layer?(index) } || layer_count
        end

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
