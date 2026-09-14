# frozen_string_literal: true

# What TileSweep adds over the arithmetic the Check suite covers: the Ruby surface, what it
# refuses, and the lifetime of the grid it reads. What its answers mean for a walker is pinned
# where a walker uses them — spec/rgame/engine/tile_blockers_spec.rb and the travel contract it
# runs, and spec/rgame/engine/components/navigator_spec.rb.
RSpec.describe RGame::Util::TileSweep do
  subject(:sweep) { described_class.new(grid, 16, 16) }

  def grid_from(rows)
    RGame::Util::SolidGrid.build(rows.first.length, rows.length) { |col, row| rows[row][col] == '#' }
  end

  # A wall down column 5, at x 80..96.
  let(:grid) { grid_from(Array.new(4) { '.....#....' }) }

  it 'is a sweep over the grid it was given, at its tile size' do
    expect([sweep.grid, sweep.tile_width, sweep.tile_height]).to eq([grid, 16.0, 16.0])
  end

  it 'snaps a step flush against a solid tile, and answers in Floats' do
    expect([sweep.resolve_x(58, 0, 16, 16, 10), sweep.resolve_x(100, 0, 16, 16, -8)]).to eql([64.0, 96.0])
  end

  it 'travels open ground and not through the wall' do
    expect([sweep.travel?(10, 20, 12, 6, 50, 10), sweep.travel?(10, 20, 12, 6, 90, 0)]).to eq([true, false])
  end

  it 'sees a change made through the grid, since it reads the grid rather than a copy' do
    expect { 4.times { grid.set_solid(5, it, false) } }
      .to change { sweep.travel?(10, 20, 12, 6, 90, 0) }.from(false).to(true)
  end

  describe 'arguments it refuses' do
    it 'refuses to sweep anything but a SolidGrid' do
      expect { described_class.new([[false]], 16, 16) }.to raise_error(TypeError)
    end

    it 'refuses a tile size that is not a positive, finite number' do
      [0, -16, Float::INFINITY, Float::NAN].each do |size|
        expect { described_class.new(grid, size, 16) }.to raise_error(ArgumentError, /tile_width/)
      end
      expect { described_class.new(grid, 16, nil) }.to raise_error(TypeError)
    end

    it 'refuses a coordinate that is not a number' do
      expect { sweep.resolve_x(nil, 0, 16, 16, 1) }.to raise_error(TypeError)
      expect { sweep.resolve_y(0, '0', 16, 16, 1) }.to raise_error(TypeError)
      expect { sweep.travel?(0, 0, 16, 16, 1, nil) }.to raise_error(TypeError)
    end

    it 'refuses a non-finite number in a step that moves' do
      expect { sweep.resolve_x(Float::NAN, 0, 16, 16, 1) }.to raise_error(FloatDomainError)
      expect { sweep.resolve_y(0, 0, Float::INFINITY, 16, 1) }.to raise_error(FloatDomainError)
      expect { sweep.travel?(0, 0, 16, 16, Float::NAN, 0) }.to raise_error(FloatDomainError)
    end

    it 'returns the box where it is from a step that does not move, whatever the numbers' do
      expect(sweep.resolve_x(Float::INFINITY, Float::NAN, 16, 16, 0)).to eq(Float::INFINITY)
    end

    it 'refuses a travel too long to sweep' do
      expect { sweep.travel?(0, 0, 16, 16, 1e20, 0) }.to raise_error(ArgumentError, /too long/)
    end

    it 'answers a coordinate far outside the grid as open ground' do
      expect(sweep.resolve_x(2**40, 0, 16, 16, 4)).to eq(2**40 + 4)
    end
  end

  describe 'memory' do
    it 'is freed when collected' do
      collect_garbage
      before = described_class.debug_live_sweeps
      build_in_finished_thread { 200.times { described_class.new(grid, 16, 16).travel?(0, 0, 4, 4, 30, 30) } }
      collect_garbage
      expect(described_class.debug_live_sweeps).to eq(before)
    end

    it 'keeps its grid alive while it is' do
      kept = described_class.new(grid_from(['..#..']), 16, 16)
      collect_garbage
      expect(kept.resolve_x(0, 0, 16, 16, 20)).to eq(16.0)
    end

    it 'survives the collector moving objects under it' do
      kept = described_class.new(grid_from(['..#..']), 16, 16)
      GC.verify_compaction_references(expand_heap: true, toward: :empty)
      expect(kept.grid.solid?(2, 0)).to be(true)
    end
  end
end
