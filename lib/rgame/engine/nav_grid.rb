# frozen_string_literal: true

module RGame
  module Engine
    # A walkability grid and the searches over it: region labels and A* routes, run in C by a
    # Util::RouteSearch over a Util::SolidGrid.
    #
    # Where TileBlockers answers *what is in the way of a step*, this answers *what is in the
    # way of a route*: the same fact about the same cells, asked over a graph instead of along
    # a box's sweep. Components::TileWorld owns both, over one store.
    #
    # It is built one of two ways:
    #
    # - **`grid:`** — over a SolidGrid it shares. A cell changed in that grid is changed here
    #   at once, and region labels follow it on the next query with nothing rebuilt. This is
    #   how a TileWorld builds one, and the way to build one over solidity that will change.
    # - **`width:`, `height:`, `solid:`** — from a callable, `solid.call(col, row) -> bool`,
    #   read once per cell into a private grid of its own. Nothing re-reads the callable, so a
    #   change behind it is never seen.
    #
    # Anything else — both, or neither — is an ArgumentError.
    #
    # Routes are cells, never pixels. Turning a cell into the point a node must reach depends
    # on the node's collider, which a grid has no business knowing; Components::Navigator
    # does that.
    #
    # The grid is 8-connected with octile costs (1 straight, √2 diagonal), and a diagonal step
    # is allowed only when both orthogonal cells beside it are open, so a route never cuts the
    # corner of a solid cell. Connected regions are labelled whenever the grid has changed
    # since they last were, which makes an unreachable goal — the answer a search is slowest
    # to give, because it has to exhaust the region first — a lookup whenever it lies in
    # another region.
    #
    # Coordinates are Integers, and anything else is a TypeError. An Integer outside the
    # grid, however large, is answered like any cell outside it.
    #
    # A search runs on demand, never per frame, and allocates its result; everything else it
    # keeps is reused between searches. One grid is therefore not safe to search from two
    # threads at once.
    class NavGrid
      def initialize(grid: nil, width: nil, height: nil, solid: nil)
        @grid = grid ? shared(grid, width, height, solid) : private_grid(width, height, solid)
        @search = Util::RouteSearch.new(@grid)
      end

      def width = @grid.width
      def height = @grid.height

      def walkable?(col, row)
        !@grid.solid?(col, row) && col >= 0 && row >= 0 && col < @grid.width && row < @grid.height
      end

      # The connected region containing the cell, as an Integer label — two walkable cells
      # share a label exactly when a route joins them — or nil for a solid cell or one
      # outside the grid.
      def region(col, row) = @search.region(col, row)

      def reachable?(from_col, from_row, to_col, to_row)
        from = @search.region(from_col, from_row)
        to = @search.region(to_col, to_row)
        !from.nil? && from == to
      end

      # The cheapest route from start to goal, both included, as `[[col, row], ...]` — or
      # nil when either end is solid, outside the grid, or in another region. Start equal
      # to goal is a route of one cell. Ties between equally cheap routes are broken the
      # same way every time, so the same query always returns the same route.
      def find(from_col, from_row, to_col, to_row) = @search.find(from_col, from_row, to_col, to_row)

      private

      def shared(grid, width, height, solid)
        return grid unless width || height || solid

        raise ArgumentError, 'a NavGrid is built over a grid: or from width:, height: and solid:, not both'
      end

      def private_grid(width, height, solid)
        unless width && height && solid
          raise ArgumentError, 'a NavGrid needs a grid:, or all of width:, height: and solid:'
        end

        Util::SolidGrid.build(width, height) { |col, row| solid.call(col, row) }
      end
    end
  end
end
