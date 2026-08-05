# frozen_string_literal: true

module Engine
  # Axis-separated AABB-vs-tile collision resolution (pure). `solid` is a callable
  # `solid.call(col, row) -> bool`. Resolve X then Y (with the X result) to get
  # wall-sliding. Assumes per-step movement smaller than a tile (no tunneling),
  # which holds for our speeds.
  class TileCollision
    EPS = 1e-9

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

    private

    # Plain integer loops rather than (a..b).any? { ... }: the Range literal would
    # allocate on this per-frame collision path.
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
