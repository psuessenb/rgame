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
      # The box is swept along the segment in overlapping windows half a tile long, moving
      # stride a quarter tile, and each window is resolved both ways round — X then Y, and
      # Y then X. A single X-then-Y staircase is not enough: at a quarter tile a step can
      # jump diagonally past a corner that the walker, moving a pixel or so at a time,
      # meets. Resolving both ways covers every position between a window's ends, and the
      # overlap covers a walker's own X-then-Y step straddling two windows, as long as that
      # step is under a quarter tile — 240 px/s at 60 ticks a second on 16 px tiles.
      #
      # Smoothing is greedy: from each corner it extends the segment cell by cell until the
      # next cell would not be clear, and turns there.
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
        SWEEP_STEP = 0.25

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
        # rubocop:disable Naming/PredicateMethod -- a command that reports whether it could be
        # carried out, not a question; `go_to?` would read as "may I go there?".
        def go_to(world_x, world_y)
          unless @world
            raise "#{mover_name}#go_to plans over the scene's TileWorld, so the node has to be " \
                  'in the tree first.'
          end

          measure_anchor
          cells = @world.nav_grid.find(*cell_at(@anchor_x, @anchor_y), *cell_at(world_x, world_y))
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

        def cell_at(x, y) = [(x / @world.tile_width).floor, (y / @world.tile_height).floor]

        def centre_x(cell) = (cell[0] + 0.5) * @world.tile_width
        def centre_y(cell) = (cell[1] + 0.5) * @world.tile_height

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
                           clear?(x, y, centre_x(cells[index + 1]), centre_y(cells[index + 1]))
          index
        end

        def clear?(from_x, from_y, to_x, to_y)
          dx = to_x - from_x
          dy = to_y - from_y
          steps = [(dx.abs / (@world.tile_width * SWEEP_STEP)).ceil,
                   (dy.abs / (@world.tile_height * SWEEP_STEP)).ceil, 1].max
          step_x = dx / steps
          step_y = dy / steps
          span = [steps, 2].min
          left = from_x - (@box_w / 2.0)
          top = from_y - (@box_h / 2.0)
          (steps - span + 1).times.all? do |sample|
            window_clear?(left + (step_x * sample), top + (step_y * sample), step_x * span, step_y * span)
          end
        end

        def window_clear?(x, y, dx, dy)
          blockers = @world.blockers
          w = @box_w
          h = @box_h
          blockers.resolve_x(x, y, w, h, dx) == x + dx &&
            blockers.resolve_y(x + dx, y, w, h, dy) == y + dy &&
            blockers.resolve_y(x, y, w, h, dy) == y + dy &&
            blockers.resolve_x(x, y + dy, w, h, dx) == x + dx
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
