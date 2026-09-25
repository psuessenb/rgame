# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # The scene-scoped tile world: a system component (it lives on the scene node and
      # is found with node.system(TileWorld)) that owns the parsed Engine::TileMap and
      # everything an actor needs from it — collision against the solid tiles, the world
      # bounds, and drawing the map through the scene's camera.
      #
      # **It does not resolve a step.** What it owns is the map's solid tiles as a blocker
      # source (#blockers, an Engine::TileBlockers); the actor that wants to be stopped by
      # them borrows it and resolves against it — see Components::Mover, which
      # builds its own Engine::CollisionSystem out of the sources its `blocked_by` names.
      # A mover may be blocked by tiles, by other actors, or by both, and only the mover
      # knows which, so the resolver is the mover's and the grid is this system's. The tile
      # solidity itself is whatever the map reports (baked per-tile in Tiled).
      # The same solidity, viewed as a graph for planning routes, is #nav_grid. A thing
      # standing on the map adds to it through Components::OccupiesCell.
      #
      # **It also knows where the floor is.** A cell holding a tile of class `gap` has no
      # floor (TileMap#gap_tile?). #floor_at? answers for a point, and #floor_reach_x and
      # #floor_reach_y say how far a point on the floor can move and stay on it, which is
      # what #gap_blockers stops a step with. The gaps are read once, into a second
      # Util::SolidGrid, as solidity is.
      #
      # **Solidity is read from the map once**, into one Util::SolidGrid, the first time
      # anything asks — and #blockers, #nav_grid and #solid? all read that store, never the
      # map. So they cannot disagree about a cell, and a resolve costs a byte lookup rather
      # than a walk through the map's layers. An occupied cell is solid in that store too,
      # with a count per cell of what occupies it.
      #
      # **It does not draw.** Drawing the map is RGame::Engine::TileMapLayer, one
      # node per Tiled layer, mounted inside the WorldView so the map is drawn
      # once per viewport like the rest of the world. This stays a system — the
      # thing actors ask about collision and bounds — and a system that also
      # drew was always the odd part of it.
      #
      # It owns the map's **animation clock**. Nothing below reads a wall clock;
      # see "`draw` renders state; time enters through `update`".
      # The elapsed seconds animated tiles run on are accumulated here and handed down at
      # draw time. Stop calling `update` and the water freezes, which is what pausing
      # should look like.
      class TileWorld < Engine::Component
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
        end

        # The map's solid tiles as a blocker source, for a body that declared
        # `blocked_by: [:tiles]`. The same source every time, so every body on the map
        # shares one.
        def blockers
          @blockers ||= Engine::TileBlockers.new(grid: solid_grid, tile_width: @map.tile_width,
                                                 tile_height: @map.tile_height)
        end

        def world_width = @map.pixel_width
        def world_height = @map.pixel_height

        # The size of one cell, in pixels.
        def tile_width = @map.tile_width
        def tile_height = @map.tile_height

        # A cell's left and top edges in world pixels, and the cell holding a world
        # position, as TileMap#cell_x, #cell_y, #col_at and #row_at answer them. The
        # cells are the ones #nav_grid plans over and #solid? answers for.
        def cell_x(col) = @map.cell_x(col)
        def cell_y(row) = @map.cell_y(row)
        def col_at(world_x) = @map.col_at(world_x)
        def row_at(world_y) = @map.row_at(world_y)

        # The middle of a cell in world pixels: where a Navigator steers to, and where
        # a thing standing on the cell stands. Two methods rather than one pair, so
        # reading one allocates nothing.
        def cell_centre_x(col) = (@map.cell_x(col) + @map.cell_x(col + 1)) / 2.0
        def cell_centre_y(row) = (@map.cell_y(row) + @map.cell_y(row + 1)) / 2.0

        def layer_count = @map.layer_count

        # The map's layer at `index`, and the index of the layer a name or
        # `'Group/layer'` path names, as `TileMap#layer` and `#layer_index`
        # answer them.
        def layer(index) = @map.layer(index)
        def layer_index(name_or_path) = @map.layer_index(name_or_path)

        # The first layer Tiled flags `above`, or the layer count if none is —
        # which is where TileMapLayer.mount leaves the gap for the actors, so a
        # map with no flag puts them over everything. Read once at mount rather
        # than per frame: which layers cover the actors is a fact about the
        # scene's arrangement, and the arrangement is made once.
        def first_above_layer
          layer_count.times.find { |index| @map.layer(index).above? } || layer_count
        end

        # Clamp a camera to this map's edges. Called for each camera the scene
        # hands over, and again for one that arrives later (a player joining).
        def bound(camera)
          camera.world_width = @map.pixel_width
          camera.world_height = @map.pixel_height
          camera
        end

        def solid?(col, row) = solid_grid.solid?(col, row)

        # The floor's edge as a blocker source, for a mover that declared
        # `blocked_by: [:gaps]`: an Engine::GapBlockers over this world. The same source
        # every time, so every mover on the map shares one.
        def gap_blockers = @gap_blockers ||= Engine::GapBlockers.new(world: self)

        # How far short of a gap's edge #floor_reach_x and #floor_reach_y stop a point, in
        # pixels: the margin Util::TileSweep keeps against a wall. A point stopped exactly on
        # the edge could cross it by rounding, on its way from a box to a node and back.
        FLOOR_EDGE = 1e-9

        # Whether any layer holds a gap tile at (col, row). A cell off the map is not a gap.
        def gap?(col, row) = gap_grid.solid?(col, row)

        # Whether the world point (x, y) is on the floor: its cell is not a gap. A point on
        # a cell's left or top edge is in that cell, and a point off the map is on the floor.
        #
        # hot-path
        def floor_at?(x, y) = !gap?(@map.col_at(x), @map.row_at(y))

        # How far the point (x, y) can move `dx` along x and stay on the floor: `dx` itself,
        # or as far as FLOOR_EDGE short of the first gap on the way. A point already off
        # the floor moves the whole way, so a node standing in a gap is never held there.
        #
        # hot-path
        def floor_reach_x(x, y, dx)
          return dx if dx.zero? || !floor_at?(x, y)

          row = @map.row_at(y)
          from = @map.col_at(x)
          to = @map.col_at(x + dx)
          if dx.positive?
            col = from + 1
            col += 1 while col <= to && !gap?(col, row)
            col > to ? dx : [@map.cell_x(col) - FLOOR_EDGE - x, 0.0].max
          else
            col = from - 1
            col -= 1 while col >= to && !gap?(col, row)
            col < to ? dx : [@map.cell_x(col + 1) + FLOOR_EDGE - x, 0.0].min
          end
        end

        # The same as #floor_reach_x, along y.
        #
        # hot-path
        def floor_reach_y(x, y, dy)
          return dy if dy.zero? || !floor_at?(x, y)

          col = @map.col_at(x)
          from = @map.row_at(y)
          to = @map.row_at(y + dy)
          if dy.positive?
            row = from + 1
            row += 1 while row <= to && !gap?(col, row)
            row > to ? dy : [@map.cell_y(row) - FLOOR_EDGE - y, 0.0].max
          else
            row = from - 1
            row -= 1 while row >= to && !gap?(col, row)
            row < to ? dy : [@map.cell_y(row + 1) + FLOOR_EDGE - y, 0.0].min
          end
        end

        # The map's solid tiles as an Engine::NavGrid, for planning a route rather than
        # resolving a step — over the same store #blockers reads, as a second view. Built on
        # first ask, and the same grid every time after.
        def nav_grid
          @nav_grid ||= Engine::NavGrid.new(grid: solid_grid)
        end

        # A cell that something on the map now blocks, as OccupiesCell reports it. The
        # cell stays solid until every occupant has vacated it, and a cell the map made
        # solid stays solid after. Raises ArgumentError for a cell outside the map.
        #
        # @api private
        def occupy(col, row)
          index = occupancy_index(col, row)
          occupants[index] += 1
          solid_grid.set_solid(col, row, true)
        end

        # One occupant of the cell has left it.
        #
        # @api private
        def vacate(col, row)
          index = occupancy_index(col, row)
          raise ArgumentError, "nothing occupies cell (#{col}, #{row})" if occupants[index].zero?

          occupants[index] -= 1
          solid_grid.set_solid(col, row, @map.solid_tile?(col, row)) if occupants[index].zero?
        end

        # Advances the tile animations. Seconds, like every other duration here.
        def _update(dt)
          @elapsed += dt
        end

        private

        def occupants = @occupants ||= Array.new(@map.width * @map.height, 0)

        def occupancy_index(col, row)
          unless @map.in_bounds?(col, row)
            raise ArgumentError, "cell (#{col}, #{row}) is outside the map, which is " \
                                 "#{@map.width}x#{@map.height} cells"
          end

          (row * @map.width) + col
        end

        def solid_grid
          @solid_grid ||= Util::SolidGrid.build(@map.width, @map.height) { |col, row| @map.solid_tile?(col, row) }
        end

        def gap_grid
          @gap_grid ||= Util::SolidGrid.build(@map.width, @map.height) { |col, row| @map.gap_tile?(col, row) }
        end
      end
    end
  end
end
