# frozen_string_literal: true

RSpec.describe RGame::Engine::SpatialHash do
  subject(:hash) { described_class.new(cell_size: 10) }

  def query(x, y, w, h)
    found = []
    hash.query(x, y, w, h) { |item| found << item }
    found
  end

  it 'returns items sharing a cell with the query region' do
    hash.insert(:a, 0, 0, 5, 5)
    hash.insert(:b, 100, 100, 5, 5)
    expect(query(1, 1, 2, 2)).to eq([:a])
  end

  it 'omits items in far-away cells' do
    hash.insert(:b, 100, 100, 5, 5)
    expect(query(0, 0, 5, 5)).to be_empty
  end

  it 'finds an item that spans several cells from any of them' do
    hash.insert(:big, 5, 5, 25, 25) # covers cells (0,0)..(3,3)
    expect(query(28, 28, 1, 1)).to include(:big)
  end

  it 'works with negative coordinates (off-screen / mid-wrap)' do
    hash.insert(:edge, -25, -25, 8, 8)
    expect(query(-24, -24, 1, 1)).to eq([:edge])
  end

  it 'clear empties the buckets but keeps the hash usable' do
    hash.insert(:a, 0, 0, 5, 5)
    hash.clear
    expect(query(0, 0, 5, 5)).to be_empty
    hash.insert(:c, 0, 0, 5, 5)
    expect(query(0, 0, 5, 5)).to eq([:c])
  end

  describe '#query_circle' do
    def query_circle(cx, cy, r)
      found = []
      hash.query_circle(cx, cy, r) { |item| found << item }
      found
    end

    it 'yields items in cells the circle bounding box covers' do
      hash.insert(:a, 0, 0, 5, 5)
      hash.insert(:b, 100, 100, 5, 5)
      expect(query_circle(2, 2, 4)).to eq([:a])
    end

    it 'omits items outside the bounding box' do
      hash.insert(:b, 100, 100, 5, 5)
      expect(query_circle(0, 0, 5)).to be_empty
    end

    it 'reaches cells a large radius spans' do
      hash.insert(:far, 25, 0, 1, 1) # cell (2, 0)
      expect(query_circle(0, 0, 30)).to include(:far) # bbox (-30..30) reaches it
    end
  end

  # cell_size is 10 here, so cell (c, r) is the square [c*10, c*10+10) x [r*10, r*10+10).
  describe '#cell_empty?' do
    it 'is true for a cell nothing was inserted into' do
      hash.insert(:a, 0, 0, 5, 5)
      expect(hash.cell_empty?(35, 35)).to be(true)
    end

    it 'is false for the cell an item was inserted into' do
      hash.insert(:a, 0, 0, 5, 5)
      expect(hash.cell_empty?(3, 3)).to be(false)
    end

    it 'takes a point anywhere inside the cell, not the item itself' do
      hash.insert(:a, 0, 0, 5, 5)
      expect(hash.cell_empty?(9, 9)).to be(false) # same cell, past the item's box
    end

    # Items are bucketed by their AABB, so a box reaching into a cell fills it even
    # where the box does not cover the point asked about.
    it 'is false for every cell an items box spans' do
      hash.insert(:big, 5, 5, 25, 25) # covers [5, 30) x [5, 30): cells (0,0)..(2,2)
      expect([hash.cell_empty?(21, 4), hash.cell_empty?(31, 4)]).to eq([false, true])
    end

    # The cell walk is half-open on the far edge, matching CollisionBox.overlap?: a box
    # ending exactly on a boundary stops at the cell before it, so a piece filling one
    # square leaves the squares it borders free.
    it 'is true for the cell a box ends exactly on' do
      hash.insert(:tile, 10, 10, 10, 10) # exactly cell (1, 1)
      expect([hash.cell_empty?(15, 15), hash.cell_empty?(25, 15),
              hash.cell_empty?(15, 25), hash.cell_empty?(5, 15)]).to eq([false, true, true, true])
    end

    it 'works with negative coordinates' do
      hash.insert(:edge, -25, -25, 8, 8)
      expect([hash.cell_empty?(-24, -24), hash.cell_empty?(-5, -5)]).to eq([false, true])
    end

    it 'reports every cell empty again after clear' do
      hash.insert(:a, 0, 0, 5, 5)
      hash.clear
      expect(hash.cell_empty?(3, 3)).to be(true)
    end

    # A miss must not create the bucket it looked for: the buckets Hash has a default
    # block that would, which would both allocate and grow the index from a read.
    it 'allocates nothing and stores nothing when the cell is empty' do
      hash.insert(:a, 0, 0, 5, 5)
      expect { hash.cell_empty?(1000, 1000) }.to allocate_nothing
      expect(query(1000, 1000, 1, 1)).to be_empty
    end
  end
end
