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
end
