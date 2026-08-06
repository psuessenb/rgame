# frozen_string_literal: true

RSpec.describe Engine::TileCollision do
  # 16px tiles; column 5 (x 80..96) is a solid wall, everything else open.
  subject(:collision) do
    described_class.new(tile_width: 16, tile_height: 16,
                        solid: ->(col, _row) { col == 5 })
  end

  let(:w) { 16 }
  let(:h) { 16 }

  it 'passes freely through open space' do
    expect(collision.resolve_x(16, 0, w, h, 4)).to eq(20)
  end

  it 'stops flush against a wall when moving right into it' do
    # Mover at x=58 (right edge 74) moving +10 would put its right edge at 84,
    # inside the wall (80..96); it snaps so the right edge rests at 80 → x=64.
    expect(collision.resolve_x(58, 0, w, h, 10)).to eq(80 - w)
  end

  it 'stops flush against a wall when moving left into it' do
    # Mover at x=100 (left edge 100) moving -8 would put its left edge at 92,
    # inside the wall; it snaps so the left edge rests at the wall's right → 96.
    expect(collision.resolve_x(100, 0, w, h, -8)).to eq(96)
  end

  it 'does not move along an axis with no input' do
    expect(collision.resolve_x(16, 0, w, h, 0)).to eq(16)
    expect(collision.resolve_y(16, 0, w, h, 0)).to eq(0)
  end

  it 'stops flush against a solid floor when moving down into it' do
    floor = described_class.new(tile_width: 16, tile_height: 16,
                                solid: ->(_col, row) { row == 5 })
    # Mover at y=60 (bottom 76) moving +10 would put its bottom at 86, inside the
    # floor row (80..96); it snaps so the bottom rests at 80 → y=64.
    expect(floor.resolve_y(0, 60, w, h, 10)).to eq(80 - h)
  end
end
