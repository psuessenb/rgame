# frozen_string_literal: true

require 'rgame/util_ext'

module RGame
  module Util
    # Which cells of a tile grid are solid: one byte a cell, in C. A value with no handle
    # behind it, which is why it lives in Util and why the engine layer may own one.
    #
    # It is the one store a tile world's solidity lives in. The blockers that stop a walker
    # and the RouteSearch that plans one both read it, so they cannot disagree about a wall,
    # and a cell changed with #set_solid is changed for both at once.
    #
    # #revision counts the changes: it moves on a #set_solid that changes a cell and on no
    # other, so anything derived from the cells — a search's region labels — can tell
    # whether it is stale without being told.
    #
    # Coordinates are Integers, and anything else is a TypeError. Outside the grid is open,
    # including an Integer too large to be inside any grid.
    #
    #   grid = RGame::Util::SolidGrid.build(8, 3) { |col, _row| col == 3 }
    #   grid.solid?(3, 1)    # => true
    #   grid.solid?(-1, 0)   # => false
    #   grid.set_solid(3, 1, false)
    #   grid.revision        # => 1
    class SolidGrid
      # A grid with each cell's solidity read from the block, once per cell, row by row.
      def self.build(width, height)
        grid = new(width, height)
        height.times do |row|
          width.times { |col| grid.set_solid(col, row, true) if yield(col, row) }
        end
        grid
      end
    end
  end
end
