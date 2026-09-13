# frozen_string_literal: true

module RGame
  module Engine
    # The tile grid as a blocker source: axis-separated AABB-vs-tile collision
    # resolution (pure). `solid` is a callable `solid.call(col, row) -> bool`, so the
    # tile source is decoupled (a TileMap, a fake in tests). Assumes per-step movement
    # smaller than a tile (no tunneling), which holds for our speeds.
    #
    # It answers the blocker-source question — "where does this box land moving dx" —
    # which CollisionSystem asks of every source it holds; see its header for the
    # protocol. Resolving X then Y (with the X result) is what gives wall-sliding, and
    # that ordering lives in the system rather than here, so every source shares it.
    #
    # Nothing needs a grid to be a blocker source: this one divides by the tile size,
    # and one over moving actors would query a broadphase instead. The arithmetic that
    # snaps a box flush against an edge is the same either way.
    class TileBlockers
      EPS = 1e-9

      # What a TileBlockers reports as having stopped a step. One object for the life of
      # the process, answering the same two questions a collider does — so a handler reads
      # `by.layer` whatever stopped it and never branches on what kind of thing it was. A
      # tile has no node, so `node` is nil.
      #
      # It holds no state at all, which is what makes one TileBlockers safe to share
      # between every body on the map: there is nothing here for two of them to race over.
      class Tiles
        def layer = :tiles
        def node = nil
      end

      TILES = Tiles.new.freeze

      def initialize(tile_width:, tile_height:, solid:)
        @tile_width = tile_width
        @tile_height = tile_height
        @solid = solid
      end

      # Move an AABB (top-left x, y; size w, h) by dx, snapping flush against solids.
      def resolve_x(x, y, w, h, dx)
        nx = x + dx
        return nx if dx.zero?

        first_row = (y / @tile_height).floor
        last_row  = ((y + h - EPS) / @tile_height).floor

        if dx.positive?
          col = ((nx + w - EPS) / @tile_width).floor
          return col * @tile_width - w if solid_in_rows?(col, first_row, last_row)
        else
          col = (nx / @tile_width).floor
          return (col + 1) * @tile_width if solid_in_rows?(col, first_row, last_row)
        end
        nx
      end

      def resolve_y(x, y, w, h, dy)
        ny = y + dy
        return ny if dy.zero?

        first_col = (x / @tile_width).floor
        last_col  = ((x + w - EPS) / @tile_width).floor

        if dy.positive?
          row = ((ny + h - EPS) / @tile_height).floor
          return row * @tile_height - h if solid_in_cols?(row, first_col, last_col)
        else
          row = (ny / @tile_height).floor
          return (row + 1) * @tile_height if solid_in_cols?(row, first_col, last_col)
        end
        ny
      end

      # The grid stopped it, and the grid is the same for everybody — so this is a
      # constant rather than a record of the last step. See TILES.
      def blocker = TILES

      # A grid does not move, so there is nothing to re-index. Part of the blocker-source
      # protocol Engine::CollisionSystem calls after every step; see its header.
      def moved(_actor, _from_x, _from_y, _w, _h) = nil

      private

      def solid_in_rows?(col, first_row, last_row)
        row = first_row
        while row <= last_row
          return true if @solid.call(col, row)

          row += 1
        end
        false
      end

      def solid_in_cols?(row, first_col, last_col)
        col = first_col
        while col <= last_col
          return true if @solid.call(col, row)

          col += 1
        end
        false
      end
    end
  end
end
