# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # A PathFollow that makes its own paths: `go_to(world_x, world_y)` plans a route
      # over the scene's tile map to the cell containing that point, and walks it.
      #
      # Planning is three steps. The scene's TileWorld#nav_grid finds the cheapest route
      # of cells; the route is **string-pulled** into as few straight segments as the
      # node's own collider can travel; and those corners become the Engine::Path this
      # component walks, exactly as a PathFollow walks one it was handed.
      #
      # ## The route is checked against what will stop the walk
      #
      # A segment is kept only if the map's own blocker source — TileWorld#blockers, the
      # object a mover declaring `:tiles` resolves its steps against — lets the collider
      # box travel it. A test on cells alone would keep a diagonal past a solid tile's
      # corner that a point clears and a 12x6 feet box clips, and a PathFollow does not
      # slide: the walker would stand at that corner.
      #
      # The question is TileBlockers#travel?, which holds for a walker stepping under a
      # quarter tile at a time — 240 px/s at 60 ticks a second on 16 px tiles.
      #
      # Smoothing is greedy: from each corner it extends the segment cell by cell until the
      # next cell would not be clear, and turns there. The next cell after a corner is taken
      # without asking, which is sound only for a collider **no larger than a tile** on
      # either axis — so `go_to` refuses a larger one rather than plan a route it may stall on.
      #
      # So what is walked is measured from the **anchor** — the centre of the sibling
      # BoxCollider's box, or the node's origin on a node with none — and a route ends
      # with the anchor on the centre of the target cell.
      #
      # ## What it does not do
      #
      # It does not replan. A route is planned against the map, and the map is all it
      # knows: a walker declaring other colliders in `blocked_by` waits behind one on its
      # route, the way any PathFollow waits, and a game that wants it to go round calls
      # `go_to` again.
      #
      # The route is planned in world space and walked in the node's parent's space, which
      # agree under an unrotated ancestor chain — the same limit a blocked Mover has.
      class Navigator < PathFollow
        # The cells of the last route `go_to` planned, start to target, before smoothing —
        # `[[col, row], ...]`, or nil before the first one. For drawing; `path` is what is
        # walked.
        attr_reader :cells

        def initialize(speed:, blocked_by: [])
          super
          @cells = nil
        end

        def on_attach
          super
          @world = node.system(TileWorld) ||
                   raise("#{mover_name} plans routes over the scene's TileWorld, and the scene " \
                         'has none. Mount one, or use a PathFollow and hand it a path.')
          @anchor = node.get_component(BoxCollider)
        end

        # Plan from where the node stands to the cell containing (world_x, world_y), and
        # start walking it from the node's current position — so a walker already on a
        # route turns onto the new one without a jump. Returns true.
        #
        # Returns false, and leaves whatever the node was doing alone, when there is no
        # route: the target is solid, outside the map, or cut off from the node.
        #
        # Raises ArgumentError when the node's collider is wider or taller than a tile:
        # pathfinding for such a collider is not supported.
        #
        # rubocop:disable Naming/PredicateMethod -- a command that reports whether it could be
        # carried out, not a question; `go_to?` would read as "may I go there?".
        def go_to(world_x, world_y)
          unless @world
            raise "#{mover_name}#go_to plans over the scene's TileWorld, so the node has to be " \
                  'in the tree first.'
          end

          measure_anchor
          refuse_a_box_larger_than_a_tile
          cells = @world.nav_grid.find(@world.col_at(@anchor_x), @world.row_at(@anchor_y),
                                       @world.col_at(world_x), @world.row_at(world_y))
          return false unless cells

          @cells = cells
          follow(Engine::Path.new(waypoints(corners(cells))))
          true
        end
        # rubocop:enable Naming/PredicateMethod

        private

        def measure_anchor
          box = @anchor&.box
          @box_w = box ? box.width : 0
          @box_h = box ? box.height : 0
          @anchor_x = node.world_x + (box ? box.offset_x + (@box_w / 2.0) : 0.0)
          @anchor_y = node.world_y + (box ? box.offset_y + (@box_h / 2.0) : 0.0)
        end

        def refuse_a_box_larger_than_a_tile
          return if @box_w <= @world.tile_width && @box_h <= @world.tile_height

          raise ArgumentError, "#{mover_name}#go_to plans for a collider no larger than a tile, and this " \
                               "node's is #{@box_w}x#{@box_h} over #{@world.tile_width}x" \
                               "#{@world.tile_height} tiles. Pathfinding for a larger collider is not supported."
        end

        def centre_x(cell) = @world.cell_centre_x(cell[0])
        def centre_y(cell) = @world.cell_centre_y(cell[1])

        def corners(cells)
          corners = [[@anchor_x, @anchor_y]]
          turn = -1
          while turn < cells.length - 1
            turn = furthest_clear(*corners.last, cells, turn + 1)
            corners << [centre_x(cells[turn]), centre_y(cells[turn])]
          end
          corners
        end

        def furthest_clear(x, y, cells, index)
          index += 1 while index < cells.length - 1 &&
                           box_travels?(x, y, centre_x(cells[index + 1]), centre_y(cells[index + 1]))
          index
        end

        def box_travels?(from_x, from_y, to_x, to_y)
          @world.blockers.travel?(from_x - (@box_w / 2.0), from_y - (@box_h / 2.0), @box_w, @box_h,
                                  to_x - from_x, to_y - from_y)
        end

        def waypoints(corners)
          shift_x = node.x - @anchor_x
          shift_y = node.y - @anchor_y
          points = corners.map { |(x, y)| [x + shift_x, y + shift_y] }
          points[0] = [node.x, node.y]
          points
        end
      end
    end
  end
end
