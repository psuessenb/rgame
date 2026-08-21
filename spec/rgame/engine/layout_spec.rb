# frozen_string_literal: true

RSpec.describe RGame::Engine::Layout do
  describe '.rects' do
    it 'gives one viewport the whole window' do
      expect(described_class.rects(1, 640, 480)).to eq([[0, 0, 640, 480]])
    end

    # Rows rather than columns: halving the height of a landscape window leaves
    # each view landscape, while halving the width leaves two tall slots that
    # fit a 2D scene badly.
    it 'stacks two viewports as rows' do
      expect(described_class.rects(2, 640, 480))
        .to eq([[0, 0, 640, 240], [0, 240, 640, 240]])
    end

    it 'puts four viewports in a 2x2 grid' do
      expect(described_class.rects(4, 640, 480))
        .to eq([[0, 0, 320, 240], [320, 0, 320, 240],
                [0, 240, 320, 240], [320, 240, 320, 240]])
    end

    it 'gives three viewports three cells of that grid, leaving the fourth empty' do
      expect(described_class.rects(3, 640, 480))
        .to eq([[0, 0, 320, 240], [320, 0, 320, 240], [0, 240, 320, 240]])
    end

    it 'has nothing to place for no viewports' do
      expect(described_class.rects(0, 640, 480)).to be_empty
    end
  end

  # A seam is a line of pixels nothing draws into. It looks like a rendering bug
  # and is really a rounding one, so the arithmetic is built to make it
  # impossible rather than unlikely.
  describe 'tiling exactly' do
    it 'covers an odd height with no gap between two rows' do
      top, bottom = described_class.rects(2, 640, 481)
      expect(top[3] + bottom[3]).to eq(481)
    end

    it 'starts the second row exactly where the first ends' do
      top, bottom = described_class.rects(2, 640, 481)
      expect(bottom[1]).to eq(top[1] + top[3])
    end

    it 'reaches the far edge of an odd window in a grid' do
      last = described_class.rects(4, 641, 481).last
      expect([last[0] + last[2], last[1] + last[3]]).to eq([641, 481])
    end

    it 'leaves no gap between grid columns' do
      left, right, = described_class.rects(4, 641, 481)
      expect(right[0]).to eq(left[0] + left[2])
    end
  end

  describe 'the primitives' do
    it 'lays out columns side by side' do
      result = []
      described_class.each_column(2, 640, 480) { |_i, x, y, w, h| result << [x, y, w, h] }
      expect(result).to eq([[0, 0, 320, 480], [320, 0, 320, 480]])
    end

    it 'lays out rows stacked' do
      result = []
      described_class.each_row(2, 640, 480) { |_i, x, y, w, h| result << [x, y, w, h] }
      expect(result).to eq([[0, 0, 640, 240], [0, 240, 640, 240]])
    end

    it 'yields each viewport its index' do
      indexes = []
      described_class.each_rect(4, 640, 480) { |i, *| indexes << i }
      expect(indexes).to eq([0, 1, 2, 3])
    end
  end

  # It runs once per frame, and building rects to throw away is exactly the kind
  # of steady drip the debug overlay's Δ/f exists to catch.
  it 'yields rects without allocating any' do
    expect { described_class.each_rect(4, 640, 480) { |_i, _x, _y, _w, _h| nil } }
      .to allocate_nothing
  end
end
