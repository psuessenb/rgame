# frozen_string_literal: true

RSpec.describe RGame::Util::SolidGrid do
  subject(:grid) { described_class.new(4, 3) }

  it 'reports its size in cells' do
    expect([grid.width, grid.height]).to eq([4, 3])
  end

  it 'starts open everywhere, at revision 0' do
    cells = (0...3).flat_map { |row| (0...4).map { |col| grid.solid?(col, row) } }
    expect([cells.uniq, grid.revision]).to eq([[false], 0])
  end

  describe '.build' do
    it 'takes each cell’s solidity from the block' do
      built = described_class.build(4, 3) { |col, row| col == row }
      expect([built.solid?(1, 1), built.solid?(2, 2), built.solid?(1, 2)]).to eq([true, true, false])
    end

    it 'asks the block once per cell, row by row' do
      asked = []
      described_class.build(3, 2) { |col, row| asked << [col, row] && false }
      expect(asked).to eq([[0, 0], [1, 0], [2, 0], [0, 1], [1, 1], [2, 1]])
    end
  end

  describe '#set_solid' do
    it 'makes one cell solid and no other' do
      grid.set_solid(2, 1, true)
      expect([grid.solid?(2, 1), grid.solid?(1, 1), grid.solid?(2, 0), grid.solid?(3, 1)])
        .to eq([true, false, false, false])
    end

    it 'opens a solid cell again' do
      grid.set_solid(2, 1, true)
      grid.set_solid(2, 1, false)
      expect(grid.solid?(2, 1)).to be(false)
    end

    it 'raises IndexError for a cell outside the grid, since a wall written nowhere is not there' do
      expect { grid.set_solid(4, 0, true) }.to raise_error(IndexError, /outside a 4x3 grid/)
    end
  end

  describe '#revision' do
    it 'moves when a cell changes' do
      grid.set_solid(1, 1, true)
      grid.set_solid(1, 1, false)
      expect(grid.revision).to eq(2)
    end

    it 'stays when a cell is set to what it already is' do
      grid.set_solid(1, 1, false)
      grid.set_solid(2, 2, true)
      grid.set_solid(2, 2, true)
      expect(grid.revision).to eq(1)
    end
  end

  describe 'outside the grid' do
    it 'is open' do
      expect([grid.solid?(-1, 0), grid.solid?(4, 0), grid.solid?(0, 3)]).to all(be(false))
    end

    it 'includes an Integer too large for any grid, rather than raising' do
      expect([grid.solid?(2**40, 0), grid.solid?(0, -(2**31) - 1), grid.solid?(2**70, 0)]).to all(be(false))
    end
  end

  describe 'arguments it refuses' do
    it 'refuses a coordinate that is not an Integer' do
      expect { grid.solid?(0.5, 0) }.to raise_error(TypeError, /Integer, got Float/)
    end

    it 'refuses a nil coordinate' do
      expect { grid.set_solid(0, nil, true) }.to raise_error(TypeError)
    end

    it 'refuses a negative size' do
      expect { described_class.new(-1, 3) }.to raise_error(ArgumentError)
    end

    it 'refuses a size whose cells an Integer index cannot reach' do
      expect { described_class.new(65_536, 65_536) }.to raise_error(ArgumentError, /more cells/)
    end

    it 'refuses a size that is not an Integer' do
      expect { described_class.new(4.0, 3) }.to raise_error(TypeError)
    end

    it 'cannot be copied, since a search holds on to the cells it was built over' do
      expect { grid.dup }.to raise_error(TypeError)
    end
  end

  describe 'an empty grid' do
    it 'has no inside' do
      empty = described_class.new(0, 5)
      expect { empty.set_solid(0, 0, true) }.to raise_error(IndexError)
    end
  end

  describe 'memory' do
    it 'frees its cells when collected' do
      collect_garbage
      before = described_class.debug_live_grids
      build_in_finished_thread { 200.times { described_class.new(32, 32) } }
      collect_garbage
      expect(described_class.debug_live_grids).to eq(before)
    end
  end
end
