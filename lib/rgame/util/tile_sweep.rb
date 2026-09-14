# frozen_string_literal: true

require 'rgame/util_ext'

module RGame
  module Util
    # An axis-aligned box against the solid tiles of a SolidGrid, in C. It reads its grid and
    # never writes it, and keeps it alive; any number of sweeps may read one grid, so a change
    # made with SolidGrid#set_solid is seen by all of them at once.
    #
    # It answers two questions with one piece of arithmetic, so they cannot disagree:
    #
    # - **#resolve_x / #resolve_y** — where the box's left (top) edge lands moving dx (dy). A
    #   step that would enter a solid tile snaps the box flush against that tile's edge. Each
    #   axis is resolved on its own. The step is assumed smaller than a tile; a longer one can
    #   pass through a tile without seeing it.
    # - **#travel?** — whether the box can move by (dx, dy) without any resolve along the way
    #   falling short of where it was heading. The box is swept in overlapping windows half a
    #   tile long, a quarter tile apart, each resolved X-then-Y and Y-then-X, which makes the
    #   answer sound for a walker that resolves its own steps and steps less than a quarter tile
    #   at a time.
    #
    # Boxes are given by their top-left corner and size, in pixels. Outside the grid is open.
    # Results are Floats. A coordinate that is not a number is a TypeError; a non-finite one is
    # a FloatDomainError, except in a resolve with no movement, which returns the box where it
    # is.
    #
    #   grid = RGame::Util::SolidGrid.build(20, 15) { |col, _row| col == 5 }  # a wall at x 80..96
    #   sweep = RGame::Util::TileSweep.new(grid, 16, 16)
    #   sweep.resolve_x(58.0, 32.0, 12, 6, 14.0)   # => 68.0, flush against the wall
    #   sweep.travel?(10.0, 32.0, 12, 6, 50.0, 0)  # => true
    #   sweep.travel?(10.0, 32.0, 12, 6, 90.0, 0)  # => false
    class TileSweep
    end
  end
end
