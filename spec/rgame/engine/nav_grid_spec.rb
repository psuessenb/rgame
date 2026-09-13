# frozen_string_literal: true

RSpec.describe RGame::Engine::NavGrid do
  # A grid drawn as rows of text, '#' solid and anything else open — so a spec shows the
  # map it is describing. The callable is the same shape a TileBlockers takes.
  def grid_from(rows)
    described_class.new(width: rows.first.length, height: rows.length,
                        solid: ->(col, row) { rows[row][col] == '#' })
  end

  # The cost of a route under the grid's own rules: 1 for a straight step, √2 for a
  # diagonal one. It also refuses a route that is not a walk at all, so an optimal-cost
  # check cannot be passed by a route that teleports.
  def route_cost(grid, route)
    route.each_cons(2).sum do |(from_col, from_row), (to_col, to_row)|
      dx = to_col - from_col
      dy = to_row - from_row
      raise "not a step: #{[from_col, from_row]} -> #{[to_col, to_row]}" unless [dx.abs, dy.abs].max == 1

      diagonal = !dx.zero? && !dy.zero?
      raise "cuts a corner at #{[from_col, from_row]}" if diagonal && !(grid.walkable?(to_col, from_row) &&
                                                                        grid.walkable?(from_col, to_row))

      diagonal ? Math.sqrt(2) : 1.0
    end
  end

  # The cheapest cost from start to every cell, by plain Dijkstra over every cell with a
  # linear scan for the minimum — slow, obvious, and sharing no code with the grid's own
  # search, which is the point of a reference.
  def dijkstra_cost(rows, from, to)
    width = rows.first.length
    height = rows.length
    open = ->(col, row) { col.between?(0, width - 1) && row.between?(0, height - 1) && rows[row][col] != '#' }
    cost = Hash.new(Float::INFINITY)
    cost[from] = 0.0
    done = {}
    neighbours = [-1, 0, 1].product([-1, 0, 1]).reject { |dx, dy| dx.zero? && dy.zero? }
    loop do
      current, current_cost = cost.reject { |cell, _| done[cell] }.min_by { |_, value| value }
      return nil if current.nil?
      return current_cost if current == to

      done[current] = true
      col, row = current
      neighbours.each do |dx, dy|
        next unless open.call(col + dx, row + dy)
        next if !dx.zero? && !dy.zero? && !(open.call(col + dx, row) && open.call(col, row + dy))

        step = dx.zero? || dy.zero? ? 1.0 : Math.sqrt(2)
        cost[[col + dx, row + dy]] = [cost[[col + dx, row + dy]], current_cost + step].min
      end
    end
  end

  # The town map's fence in miniature: a wall the full width of the map with one gap,
  # three cells wide and well off-centre.
  let(:fence) do
    [
      '................',
      '................',
      '..#.............',
      '................',
      '#####...########',
      '................',
      '...........#....',
      '................'
    ]
  end

  let(:scattered) do
    [
      '.....#......#...',
      '.##..#..##..#.#.',
      '..#.....#.......',
      '..#.###.#.####..',
      '......#......#..',
      '.####.#.####.#.#',
      '.....#.......#..',
      '.#.......##.....'
    ]
  end

  # Two open areas a wall separates completely.
  let(:islands) do
    [
      '...#....',
      '...#....',
      '...#....'
    ]
  end

  describe 'the grid' do
    subject(:grid) { grid_from(islands) }

    it 'reports its size in cells' do
      expect([grid.width, grid.height]).to eq([8, 3])
    end

    it 'is walkable on an open cell and not on a solid one' do
      expect([grid.walkable?(0, 0), grid.walkable?(3, 1)]).to eq([true, false])
    end

    it 'is not walkable outside itself' do
      expect([grid.walkable?(-1, 0), grid.walkable?(8, 0), grid.walkable?(0, 3)]).to all(be(false))
    end

    describe '#region' do
      it 'labels two cells a route joins with the same Integer' do
        expect(grid.region(0, 0)).to be_an(Integer).and eq(grid.region(2, 2))
      end

      it 'labels cells on either side of a wall differently' do
        expect(grid.region(0, 0)).not_to eq(grid.region(4, 0))
      end

      it 'is nil for a solid cell and outside the grid' do
        expect([grid.region(3, 0), grid.region(-1, 0), grid.region(0, 3)]).to all(be_nil)
      end

      it 'joins cells only orthogonally, since a diagonal past two solids is no route' do
        pinch = grid_from(['.#', '#.'])
        expect(pinch.region(0, 0)).not_to eq(pinch.region(1, 1))
      end
    end

    describe '#reachable?' do
      it 'is true within a region' do
        expect(grid.reachable?(0, 0, 2, 2)).to be(true)
      end

      it 'is false across regions, onto a solid cell, and off the grid' do
        expect([grid.reachable?(0, 0, 4, 0), grid.reachable?(0, 0, 3, 0),
                grid.reachable?(0, 0, 9, 0), grid.reachable?(3, 0, 3, 0)]).to all(be(false))
      end
    end
  end

  describe '#find' do
    it 'returns every cell of a straight corridor in order, both ends included' do
      grid = grid_from(['#####', '.....', '#####'])
      expect(grid.find(0, 1, 4, 1)).to eq([[0, 1], [1, 1], [2, 1], [3, 1], [4, 1]])
    end

    it 'returns the one cell when start and goal are the same' do
      expect(grid_from(fence).find(5, 5, 5, 5)).to eq([[5, 5]])
    end

    it 'walks a diagonal across open ground' do
      expect(grid_from(['...', '...', '...']).find(0, 0, 2, 2)).to eq([[0, 0], [1, 1], [2, 2]])
    end

    describe 'what it refuses' do
      subject(:grid) { grid_from(islands) }

      it 'is nil from a solid start' do
        expect(grid.find(3, 0, 0, 0)).to be_nil
      end

      it 'is nil to a solid goal' do
        expect(grid.find(0, 0, 3, 1)).to be_nil
      end

      it 'is nil with either end off the grid' do
        expect([grid.find(-1, 0, 0, 0), grid.find(0, 0, 0, 3)]).to all(be_nil)
      end

      it 'is nil to a goal in another region' do
        expect(grid.find(0, 0, 7, 2)).to be_nil
      end

      # Unreachable is the answer a search is slowest to give, because it has to exhaust
      # the region first; region labels make it a lookup. What is observable from outside is
      # that nothing about the map is read again to give it.
      it 'answers another region from what it read at construction' do
        solid = instance_double(Proc)
        allow(solid).to receive(:call) { |col, _row| col == 3 }
        built = described_class.new(width: 8, height: 3, solid: solid)

        expect(built.find(0, 0, 7, 2)).to be_nil
        expect(solid).to have_received(:call).exactly(24).times
      end
    end

    describe 'corners' do
      it 'never steps diagonally between two solids that share a corner' do
        expect(grid_from(['.#', '#.']).find(0, 0, 1, 1)).to be_nil
      end

      it 'goes round a single solid corner rather than across it' do
        grid = grid_from(['.#', '..'])
        expect(grid.find(0, 0, 1, 1)).to eq([[0, 0], [0, 1], [1, 1]])
      end
    end

    describe 'the fence' do
      subject(:grid) { grid_from(fence) }

      it 'routes through the gap and nowhere else' do
        crossings = grid.find(0, 7, 15, 0).select { |_col, row| row == 4 }
        expect(crossings).to contain_exactly([be_between(5, 7), 4])
      end
    end

    describe 'optimal cost' do
      {
        'fence' => [[0, 7], [15, 0]],
        'fence, from beside the wall' => [[14, 5], [0, 3]],
        'scattered' => [[0, 0], [15, 7]],
        'scattered, the long way round' => [[3, 2], [14, 0]],
        'islands' => [[0, 2], [2, 0]]
      }.each do |name, (from, to)|
        it "matches a brute-force Dijkstra: #{name}" do
          rows = send(name.split(',').first.to_sym)
          grid = grid_from(rows)
          route = grid.find(*from, *to)

          expect([route.first, route.last, route_cost(grid, route)])
            .to match([from, to, be_within(1e-9).of(dijkstra_cost(rows, from, to))])
        end
      end

      it 'matches it from one corner to every open cell of the scattered grid' do
        grid = grid_from(scattered)
        cells = (0...8).flat_map { |row| (0...16).map { |col| [col, row] } }
        open_cells = cells.select { |cell| grid.walkable?(*cell) }
        from = open_cells.first
        mismatches = open_cells.reject do |to|
          route = grid.find(*from, *to)
          expected = dijkstra_cost(scattered, from, to)
          route.nil? ? expected.nil? : (route_cost(grid, route) - expected).abs < 1e-9
        end

        expect(mismatches).to be_empty
      end
    end

    describe 'determinism' do
      subject(:grid) { grid_from(scattered) }

      it 'returns the same route for the same query' do
        first = grid.find(0, 0, 15, 7)
        expect(grid.find(0, 0, 15, 7)).to eq(first)
      end

      # The search buffers are reused between searches, so this is what catches one
      # search's leftovers steering the next.
      it 'returns the same route after an unrelated search as before it' do
        before = grid.find(0, 0, 15, 7)
        grid.find(15, 0, 0, 7)
        grid.find(9, 2, 9, 2)
        expect(grid.find(0, 0, 15, 7)).to eq(before)
      end

      it 'returns what a freshly built grid returns' do
        grid.find(15, 0, 0, 7)
        expect(grid.find(0, 0, 15, 7)).to eq(grid_from(scattered).find(0, 0, 15, 7))
      end
    end
  end
end
