# frozen_string_literal: true

require 'rgame/util_ext'

module RGame
  module Util
    # Connected regions and A* routes over a SolidGrid, in C. The search reads its grid and
    # never writes it, and keeps it alive; any number of searches may read one grid.
    #
    # The grid is 8-connected with octile costs (1 straight, √2 diagonal), and a diagonal
    # step is allowed only when both orthogonal cells beside it are open, so a route never
    # cuts the corner of a solid cell. Routes are cells, `[[col, row], ...]`, start and goal
    # included — or nil when either end is solid, outside the grid, or in another region.
    #
    # Regions are labelled on the first ask after the grid's #revision moves, so a goal in
    # another region is a lookup rather than a search that exhausts the map, and it stays
    # right when the grid changes. Everything else a search keeps between queries is reused,
    # so a repeated query allocates nothing but its result. One search is therefore not safe
    # to use from two threads at once; two searches over one grid are.
    #
    #   grid = RGame::Util::SolidGrid.build(8, 3) { |col, row| col == 3 && row < 2 }
    #   search = RGame::Util::RouteSearch.new(grid)
    #   search.find(0, 0, 7, 0)   # => [[0, 0], [1, 1], [2, 2], [3, 2], [4, 2], [5, 1], [6, 0], [7, 0]]
    class RouteSearch
    end
  end
end
