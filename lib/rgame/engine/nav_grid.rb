# frozen_string_literal: true

module RGame
  module Engine
    # A walkability grid and the searches over it (pure). Built once from a solidity
    # callable — the same `solid.call(col, row) -> bool` an Engine::TileBlockers takes —
    # and never re-read, so a map that changes needs a new grid.
    #
    # Where TileBlockers answers *what is in the way of a step*, this answers *what is in
    # the way of a route*: the same fact about the same cells, asked over a graph instead
    # of along a box's sweep. Components::TileWorld owns both, over the same map.
    #
    # Routes are cells, never pixels. Turning a cell into the point a node must reach
    # depends on the node's collider, which a grid has no business knowing.
    #
    # The grid is 8-connected with octile costs (1 straight, √2 diagonal), and a diagonal
    # step is allowed only when both orthogonal cells beside it are open, so a route never
    # cuts the corner of a solid cell. Connected regions are labelled at construction,
    # which makes an unreachable goal — the answer a search is slowest to give, because it
    # has to exhaust the region first — an O(1) `nil` whenever it lies in another region.
    #
    # A search runs on demand, never per frame, and allocates its result. Its bookkeeping
    # lives in buffers kept between searches, with a generation counter marking which
    # entries are current, so a search costs no setup proportional to the grid. One grid
    # is therefore not safe to search from two threads at once.
    class NavGrid
      DIAGONAL = Math.sqrt(2)
      DIAGONAL_EXTRA = DIAGONAL - 1.0

      attr_reader :width, :height

      def initialize(width:, height:, solid:)
        @width = width
        @height = height
        @solid = Array.new(width * height) { |index| solid.call(index % width, index / width) ? true : false }
        @regions = Array.new(width * height)
        label_regions
        allocate_search_buffers
      end

      def walkable?(col, row) = inside?(col, row) && !@solid[(row * @width) + col]

      # The connected region containing the cell, as an Integer label — two walkable cells
      # share a label exactly when a route joins them — or nil for a solid cell or one
      # outside the grid.
      def region(col, row)
        return nil unless inside?(col, row)

        @regions[(row * @width) + col]
      end

      def reachable?(from_col, from_row, to_col, to_row)
        from = region(from_col, from_row)
        !from.nil? && from == region(to_col, to_row)
      end

      # The cheapest route from start to goal, both included, as `[[col, row], ...]` — or
      # nil when either end is solid, outside the grid, or in another region. Start equal
      # to goal is a route of one cell. Ties between equally cheap routes are broken the
      # same way every time, so the same query always returns the same route.
      def find(from_col, from_row, to_col, to_row)
        return nil unless reachable?(from_col, from_row, to_col, to_row)

        start = (from_row * @width) + from_col
        goal = (to_row * @width) + to_col
        search(start, goal, to_col, to_row)
        route_to(goal)
      end

      private

      def inside?(col, row) = col >= 0 && row >= 0 && col < @width && row < @height

      def label_regions
        stack = []
        label = 0
        @solid.each_index do |index|
          next if @solid[index] || @regions[index]

          flood(index, label, stack)
          label += 1
        end
      end

      def flood(seed, label, stack)
        @regions[seed] = label
        stack.push(seed)
        until stack.empty?
          index = stack.pop
          col = index % @width
          claim(index - 1, label, stack) if col.positive?
          claim(index + 1, label, stack) if col < @width - 1
          claim(index - @width, label, stack) if index >= @width
          claim(index + @width, label, stack) if index < @solid.length - @width
        end
      end

      def claim(index, label, stack)
        return if @solid[index] || @regions[index]

        @regions[index] = label
        stack.push(index)
      end

      def allocate_search_buffers
        cells = @width * @height
        @cost = Array.new(cells, 0.0)
        @parent = Array.new(cells, -1)
        @seen = Array.new(cells, 0)
        @closed = Array.new(cells, 0)
        @generation = 0
        @heap_cell = []
        @heap_total = []
        @heap_remaining = []
        @heap_size = 0
      end

      def search(start, goal, goal_col, goal_row)
        @generation += 1
        @heap_size = 0
        relax(-1, start, 0.0, goal_col, goal_row)

        while @heap_size.positive?
          index = pop
          next if @closed[index] == @generation
          return if index == goal

          @closed[index] = @generation
          expand(index, goal_col, goal_row)
        end
      end

      def expand(index, goal_col, goal_row)
        width = @width
        col = index % width
        west = col.positive? && !@solid[index - 1]
        east = col < width - 1 && !@solid[index + 1]
        north = index >= width && !@solid[index - width]
        south = index < @solid.length - width && !@solid[index + width]
        straight = @cost[index] + 1.0
        diagonal = @cost[index] + DIAGONAL

        relax(index, index - 1, straight, goal_col, goal_row) if west
        relax(index, index + 1, straight, goal_col, goal_row) if east
        relax(index, index - width, straight, goal_col, goal_row) if north
        relax(index, index + width, straight, goal_col, goal_row) if south
        relax(index, index - width - 1, diagonal, goal_col, goal_row) if north && west
        relax(index, index - width + 1, diagonal, goal_col, goal_row) if north && east
        relax(index, index + width - 1, diagonal, goal_col, goal_row) if south && west
        relax(index, index + width + 1, diagonal, goal_col, goal_row) if south && east
      end

      def relax(from, to, cost, goal_col, goal_row)
        generation = @generation
        return if @closed[to] == generation || @solid[to]
        return if @seen[to] == generation && @cost[to] <= cost

        @seen[to] = generation
        @cost[to] = cost
        @parent[to] = from
        dx = (to % @width - goal_col).abs
        dy = (to / @width - goal_row).abs
        remaining = dx < dy ? dy + (DIAGONAL_EXTRA * dx) : dx + (DIAGONAL_EXTRA * dy)
        push(to, cost + remaining, remaining)
      end

      def push(index, total, remaining)
        slot = @heap_size
        @heap_size += 1
        while slot.positive?
          up = (slot - 1) >> 1
          up_total = @heap_total[up]
          break if up_total < total || (up_total == total && @heap_remaining[up] <= remaining)

          @heap_cell[slot] = @heap_cell[up]
          @heap_total[slot] = up_total
          @heap_remaining[slot] = @heap_remaining[up]
          slot = up
        end
        @heap_cell[slot] = index
        @heap_total[slot] = total
        @heap_remaining[slot] = remaining
      end

      def pop
        top = @heap_cell[0]
        size = @heap_size -= 1
        return top if size.zero?

        index = @heap_cell[size]
        total = @heap_total[size]
        remaining = @heap_remaining[size]
        slot = 0
        while (child = (slot << 1) + 1) < size
          right = child + 1
          child = right if right < size && before?(right, child)
          child_total = @heap_total[child]
          break if total < child_total || (total == child_total && remaining <= @heap_remaining[child])

          @heap_cell[slot] = @heap_cell[child]
          @heap_total[slot] = child_total
          @heap_remaining[slot] = @heap_remaining[child]
          slot = child
        end
        @heap_cell[slot] = index
        @heap_total[slot] = total
        @heap_remaining[slot] = remaining
        top
      end

      def before?(slot, other)
        total = @heap_total[slot]
        other_total = @heap_total[other]
        total < other_total || (total == other_total && @heap_remaining[slot] < @heap_remaining[other])
      end

      def route_to(goal)
        route = []
        index = goal
        while index != -1
          route.push([index % @width, index / @width])
          index = @parent[index]
        end
        route.reverse!
      end
    end
  end
end
