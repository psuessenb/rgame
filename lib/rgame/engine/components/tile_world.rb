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
      # floor (TileMap#gap_tile?), except where a Components::Platform's box covers it.
      # #floor_at? answers for a point, and #ground_at? the same without the platforms.
      # #floor_reach_x and #floor_reach_y say how far a point on the floor can move and
      # stay on it, which is what #gap_blockers stops a step with. #platform_under says
      # which platform a point over a gap stands on. The gaps are read once, into a second
      # Util::SolidGrid, as solidity is; the platforms move, so they are asked every time.
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

        sealed_reader :tilemap_id, :elapsed

        # `cameras` are the cameras this map bounds — every player's, normally.
        # A camera may not show past the world's edges, and this is what knows
        # how big the world is; the cameras themselves are owned by players.
        def initialize(map:, tilemap_id:, cameras: [])
          super()
          @rgame_map = map
          @rgame_tilemap_id = tilemap_id
          @rgame_elapsed = 0.0
          @rgame_platforms = []
          Array(cameras).each { |camera| bound(camera) }
        end

        # The map's solid tiles as a blocker source, for a body that declared
        # `blocked_by: [:tiles]`. The same source every time, so every body on the map
        # shares one.
        def blockers
          @rgame_blockers ||= Engine::TileBlockers.new(grid: solid_grid, tile_width: @rgame_map.tile_width,
                                                       tile_height: @rgame_map.tile_height)
        end

        def world_width = @rgame_map.pixel_width
        def world_height = @rgame_map.pixel_height

        # The size of one cell, in pixels.
        def tile_width = @rgame_map.tile_width
        def tile_height = @rgame_map.tile_height

        # A cell's left and top edges in world pixels, and the cell holding a world
        # position, as TileMap#cell_x, #cell_y, #col_at and #row_at answer them. The
        # cells are the ones #nav_grid plans over and #solid? answers for.
        def cell_x(col) = @rgame_map.cell_x(col)
        def cell_y(row) = @rgame_map.cell_y(row)
        def col_at(world_x) = @rgame_map.col_at(world_x)
        def row_at(world_y) = @rgame_map.row_at(world_y)

        # The middle of a cell in world pixels: where a Navigator steers to, and where
        # a thing standing on the cell stands. Two methods rather than one pair, so
        # reading one allocates nothing.
        def cell_centre_x(col) = (@rgame_map.cell_x(col) + @rgame_map.cell_x(col + 1)) / 2.0
        def cell_centre_y(row) = (@rgame_map.cell_y(row) + @rgame_map.cell_y(row + 1)) / 2.0

        def layer_count = @rgame_map.layer_count

        # The map's layer at `index`, and the index of the layer a name or
        # `'Group/layer'` path names, as `TileMap#layer` and `#layer_index`
        # answer them.
        def layer(index) = @rgame_map.layer(index)
        def layer_index(name_or_path) = @rgame_map.layer_index(name_or_path)

        # The first layer Tiled flags `above`, or the layer count if none is —
        # which is where TileMapLayer.mount leaves the slot for the actors, so a
        # map with no flag puts them over everything. Read once at mount rather
        # than per frame: which layers cover the actors is a fact about the
        # scene's arrangement, and the arrangement is made once.
        def first_above_layer
          layer_count.times.find { |index| @rgame_map.layer(index).above? } || layer_count
        end

        # The index of the object layer the designer marked `actors`, or `nil`
        # when none is, as `TileMap#actors_layer` answers it.
        def actors_layer = @rgame_map.actors_layer

        # Clamp a camera to this map's edges. Called for each camera the scene
        # hands over, and again for one that arrives later (a player joining).
        def bound(camera)
          camera.world_width = @rgame_map.pixel_width
          camera.world_height = @rgame_map.pixel_height
          camera
        end

        def solid?(col, row) = solid_grid.solid?(col, row)

        # The floor's edge as a blocker source, for a mover that declared
        # `blocked_by: [:gaps]`: an Engine::GapBlockers over this world. The same source
        # every time, so every mover on the map shares one.
        def gap_blockers = @rgame_gap_blockers ||= Engine::GapBlockers.new(world: self)

        # How far short of a gap's edge #floor_reach_x and #floor_reach_y stop a point, in
        # pixels: the margin Util::TileSweep keeps against a wall. A point stopped exactly on
        # the edge could cross it by rounding, on its way from a box to a node and back.
        FLOOR_EDGE = 1e-9

        # Whether any layer holds a gap tile at (col, row). A cell off the map is not a gap.
        def gap?(col, row) = gap_grid.solid?(col, row)

        # Whether the world point (x, y) is on the floor: its cell is not a gap, or a
        # platform covers it. A point on a cell's left or top edge is in that cell, and a
        # point off the map is on the floor.
        #
        # hot-path
        def floor_at?(x, y) = !gap?(@rgame_map.col_at(x), @rgame_map.row_at(y)) || !platform_covering(x, y).nil?

        # Whether the cell holding the world point (x, y) is ground: no layer has a gap
        # tile there. A platform over a gap does not make it ground, so this is #floor_at?
        # with the platforms left out: where a thing may stand and stay, such as a
        # Respawn's point.
        def ground_at?(x, y) = !gap?(@rgame_map.col_at(x), @rgame_map.row_at(y))

        # The platform a node standing at the world point (x, y) rides: the first one
        # registered whose box covers the point, where the cell is a gap. nil wherever the
        # cell is ground, whatever covers it.
        #
        # hot-path
        def platform_under(x, y)
          return nil unless gap?(@rgame_map.col_at(x), @rgame_map.row_at(y))

          platform_covering(x, y)
        end

        # How far the point (x, y) can move `dx` along x and stay on the floor: `dx` itself,
        # or as far as FLOOR_EDGE short of where the floor ends on the way. Ground and
        # platforms make one floor, so a point walks from one onto the other wherever they
        # meet or overlap. A point already off the floor moves the whole way, so a node
        # standing in a gap is never held there.
        #
        # hot-path
        def floor_reach_x(x, y, dx)
          return dx if dx.zero? || !floor_at?(x, y)

          target = x + dx
          to = @rgame_map.col_at(target)
          row = @rgame_map.row_at(y)
          at = x
          reach = nil
          if dx.positive?
            while reach.nil?
              far = floor_end_x(at, y, row, to)
              if far > target
                reach = dx
              elsif floor_at?(far, y)
                at = far
              else
                reach = [far - FLOOR_EDGE - x, 0.0].max
              end
            end
          else
            while reach.nil?
              near = floor_start_x(at, y, row, to)
              if near <= target
                reach = dx
              elsif floor_at?(near - FLOOR_EDGE, y)
                at = near - FLOOR_EDGE
              else
                reach = [near + FLOOR_EDGE - x, 0.0].min
              end
            end
          end
          reach
        end

        # The same as #floor_reach_x, along y.
        #
        # hot-path
        def floor_reach_y(x, y, dy)
          return dy if dy.zero? || !floor_at?(x, y)

          target = y + dy
          to = @rgame_map.row_at(target)
          col = @rgame_map.col_at(x)
          at = y
          reach = nil
          if dy.positive?
            while reach.nil?
              far = floor_end_y(x, at, col, to)
              if far > target
                reach = dy
              elsif floor_at?(x, far)
                at = far
              else
                reach = [far - FLOOR_EDGE - y, 0.0].max
              end
            end
          else
            while reach.nil?
              near = floor_start_y(x, at, col, to)
              if near <= target
                reach = dy
              elsif floor_at?(x, near - FLOOR_EDGE)
                at = near - FLOOR_EDGE
              else
                reach = [near + FLOOR_EDGE - y, 0.0].min
              end
            end
          end
          reach
        end

        # A platform whose box is now floor over the gaps, as Platform reports it on
        # attaching. Raises ArgumentError for one already registered.
        #
        # @api private
        def bridge(platform)
          raise ArgumentError, 'that platform is already bridging this world' if @rgame_platforms.include?(platform)

          @rgame_platforms << platform
        end

        # A platform that has left.
        #
        # @api private
        def unbridge(platform) = @rgame_platforms.delete(platform)

        # The map's solid tiles as an Engine::NavGrid, for planning a route rather than
        # resolving a step — over the same store #blockers reads, as a second view. Built on
        # first ask, and the same grid every time after.
        def nav_grid
          @rgame_nav_grid ||= Engine::NavGrid.new(grid: solid_grid)
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
          solid_grid.set_solid(col, row, @rgame_map.solid_tile?(col, row)) if occupants[index].zero?
        end

        # Advances the tile animations. Seconds, like every other duration here.
        def _update(dt)
          @rgame_elapsed += dt
        end

        private

        def platform_covering(x, y)
          i = 0
          while i < @rgame_platforms.size
            platform = @rgame_platforms[i]
            return platform if platform.covers?(x, y)

            i += 1
          end
          nil
        end

        def floor_end_x(at, y, row, to)
          far = at
          col = @rgame_map.col_at(at)
          unless gap?(col, row)
            col += 1
            col += 1 while col <= to && !gap?(col, row)
            far = @rgame_map.cell_x(col)
          end
          i = 0
          while i < @rgame_platforms.size
            platform = @rgame_platforms[i]
            far = platform.right if platform.covers?(at, y) && platform.right > far
            i += 1
          end
          far
        end

        def floor_start_x(at, y, row, to)
          near = at
          col = @rgame_map.col_at(at)
          unless gap?(col, row)
            col -= 1
            col -= 1 while col >= to && !gap?(col, row)
            near = @rgame_map.cell_x(col + 1)
          end
          i = 0
          while i < @rgame_platforms.size
            platform = @rgame_platforms[i]
            near = platform.left if platform.covers?(at, y) && platform.left < near
            i += 1
          end
          near
        end

        def floor_end_y(x, at, col, to)
          far = at
          row = @rgame_map.row_at(at)
          unless gap?(col, row)
            row += 1
            row += 1 while row <= to && !gap?(col, row)
            far = @rgame_map.cell_y(row)
          end
          i = 0
          while i < @rgame_platforms.size
            platform = @rgame_platforms[i]
            far = platform.bottom if platform.covers?(x, at) && platform.bottom > far
            i += 1
          end
          far
        end

        def floor_start_y(x, at, col, to)
          near = at
          row = @rgame_map.row_at(at)
          unless gap?(col, row)
            row -= 1
            row -= 1 while row >= to && !gap?(col, row)
            near = @rgame_map.cell_y(row + 1)
          end
          i = 0
          while i < @rgame_platforms.size
            platform = @rgame_platforms[i]
            near = platform.top if platform.covers?(x, at) && platform.top < near
            i += 1
          end
          near
        end

        def occupants = @rgame_occupants ||= Array.new(@rgame_map.width * @rgame_map.height, 0)

        def occupancy_index(col, row)
          unless @rgame_map.in_bounds?(col, row)
            raise ArgumentError, "cell (#{col}, #{row}) is outside the map, which is " \
                                 "#{@rgame_map.width}x#{@rgame_map.height} cells"
          end

          (row * @rgame_map.width) + col
        end

        def solid_grid
          @rgame_solid_grid ||= Util::SolidGrid.build(@rgame_map.width, @rgame_map.height) { |col, row| @rgame_map.solid_tile?(col, row) }
        end

        def gap_grid
          @rgame_gap_grid ||= Util::SolidGrid.build(@rgame_map.width, @rgame_map.height) { |col, row| @rgame_map.gap_tile?(col, row) }
        end
      end
    end
  end
end
