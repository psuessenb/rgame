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
end
