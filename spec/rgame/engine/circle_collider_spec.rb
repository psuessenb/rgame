# frozen_string_literal: true

RSpec.describe RGame::Engine::CircleCollider do
  describe '.overlap?' do
    it 'is true when the circles intersect' do
      expect(described_class.overlap?(0, 0, 5, 6, 0, 5)).to be(true)
    end

    it 'is true when they exactly touch (distance == sum of radii)' do
      expect(described_class.overlap?(0, 0, 4, 10, 0, 6)).to be(true)
    end

    it 'is false when they are apart' do
      expect(described_class.overlap?(0, 0, 5, 20, 0, 5)).to be(false)
    end
  end

  describe '#aabb' do
    it 'is the bounding box centred on the point' do
      expect(described_class.new(radius: 8).aabb(100, 50)).to eq([92, 42, 16, 16])
    end
  end
end
