# frozen_string_literal: true

RSpec.describe RGame::Engine::CollisionBox do
  it 'centers horizontally and anchors to the bottom (player 16x32, box 16x16)' do
    box = described_class.bottom_anchored(sprite_width: 16, sprite_height: 32, width: 16, height: 16)
    expect([box.offset_x, box.offset_y, box.width, box.height]).to eq([0, 16, 16, 16])
  end

  it 'centers horizontally and anchors to the bottom (Male 32x32, box 16x16)' do
    box = described_class.bottom_anchored(sprite_width: 32, sprite_height: 32, width: 16, height: 16)
    expect([box.offset_x, box.offset_y, box.width, box.height]).to eq([8, 16, 16, 16])
  end

  it 'computes a world-space aabb from an actor origin' do
    box = described_class.new(offset_x: 8, offset_y: 16, width: 16, height: 16)
    expect(box.aabb(100, 200)).to eq([108, 216, 16, 16])
  end

  describe '.overlap?' do
    it 'is true when two rectangles intersect' do
      expect(described_class.overlap?(0, 0, 20, 20, 10, 10, 20, 20)).to be(true)
    end

    it 'is false when they are apart on one axis' do
      expect(described_class.overlap?(0, 0, 20, 20, 10, 50, 20, 20)).to be(false)
    end

    # A rect spans [x, x + w), so two that share an edge are apart. Without this a
    # board of cell-sized pieces reports every neighbour as a contact — a fruit
    # collected by passing the square next to it.
    it 'treats shapes that only share an edge as apart' do
      expect(described_class.overlap?(0, 0, 20, 20, 20, 0, 20, 20)).to be(false)
    end

    it 'is true for the smallest real overlap' do
      expect(described_class.overlap?(0, 0, 20, 20, 19, 0, 20, 20)).to be(true)
    end
  end

  describe '.overlap_circle?' do
    it 'is true when the circle reaches an edge' do
      expect(described_class.overlap_circle?(0, 0, 20, 20, 28, 10, 10)).to be(true)
    end

    it 'is false when the circle only grazes the edge' do
      expect(described_class.overlap_circle?(0, 0, 20, 20, 30, 10, 10)).to be(false)
    end

    it 'is false when the circle clears the nearest corner' do
      # 10px past each corner axis is ~14.1px from the corner itself, so a radius of
      # 10 misses even though the circle's bounding box overlaps the rectangle.
      expect(described_class.overlap_circle?(0, 0, 20, 20, 30, 30, 10)).to be(false)
    end

    it 'is true when the circle centre is inside the rectangle' do
      expect(described_class.overlap_circle?(0, 0, 20, 20, 10, 10, 1)).to be(true)
    end
  end
end
