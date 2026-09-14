# frozen_string_literal: true

# What RouteSearch adds over the SolidGrid it reads. The route rules themselves — optimal
# cost, corners, determinism — are pinned once, in spec/rgame/engine/nav_grid_spec.rb, over the
# search the engine plans with.
RSpec.describe RGame::Util::RouteSearch do
  def grid_from(rows)
    RGame::Util::SolidGrid.build(rows.first.length, rows.length) { |col, row| rows[row][col] == '#' }
  end

  subject(:search) { described_class.new(grid) }

  let(:grid) do
    grid_from([
                '.....',
                '.....',
                '.....'
              ])
  end

  it 'is a search over the grid it was given' do
    expect(search.grid).to be(grid)
  end

  it 'finds a route as cells, both ends included' do
    expect(search.find(0, 1, 4, 1)).to eq([[0, 1], [1, 1], [2, 1], [3, 1], [4, 1]])
  end

  describe 'following the grid' do
    def wall(solid) = 3.times { |row| grid.set_solid(2, row, solid) }

    it 'splits a region walled in two, with no rebuild' do
      search.region(0, 0)
      wall(true)
      expect([search.region(0, 0) == search.region(4, 2), search.find(0, 0, 4, 2)]).to eq([false, nil])
    end

    it 'joins the two again when the wall opens, and routes through' do
      wall(true)
      search.region(0, 0)
      grid.set_solid(2, 1, false)
      expect([search.region(0, 0) == search.region(4, 2), search.find(0, 1, 4, 1)&.length]).to eq([true, 5])
    end

    it 'sees a change made through the grid by anyone, since both searches read one store' do
      other = described_class.new(grid)
      wall(true)
      expect([search.find(0, 0, 4, 0), other.find(0, 0, 4, 0)]).to eq([nil, nil])
    end
  end

  describe 'arguments it refuses' do
    it 'refuses to search anything but a SolidGrid' do
      expect { described_class.new([[false]]) }.to raise_error(TypeError)
    end

    it 'refuses a Float coordinate' do
      expect { search.find(0.5, 0, 3, 0) }.to raise_error(TypeError)
    end

    it 'refuses a nil coordinate, even when another one is already outside' do
      expect { search.find(2**40, 0, nil, 0) }.to raise_error(TypeError)
    end

    it 'answers an Integer beyond any grid as outside' do
      expect([search.find(0, 0, 2**40, 0), search.region(-(2**40), 0)]).to eq([nil, nil])
    end
  end

  describe 'memory' do
    it 'frees its buffers when collected' do
      collect_garbage
      before = described_class.debug_live_searches
      build_in_finished_thread { 200.times { described_class.new(grid).find(0, 0, 4, 2) } }
      collect_garbage
      expect(described_class.debug_live_searches).to eq(before)
    end

    it 'keeps its grid alive while it is' do
      kept = described_class.new(grid_from(['..#..', '.....']))
      collect_garbage
      expect(kept.find(0, 0, 4, 0)).to eq([[0, 0], [1, 1], [2, 1], [3, 1], [4, 0]])
    end

    it 'survives the collector moving objects under it' do
      kept = described_class.new(grid_from(['..#..', '.....']))
      GC.verify_compaction_references(expand_heap: true, toward: :empty)
      expect(kept.grid.solid?(2, 0)).to be(true)
    end
  end
end
