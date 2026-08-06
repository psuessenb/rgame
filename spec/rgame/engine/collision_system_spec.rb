# frozen_string_literal: true

RSpec.describe RGame::Engine::CollisionSystem do
  # Minimal actor: just what the system touches (x, y, collision_box).
  let(:actor_class) { Struct.new(:x, :y, :collision_box) }
  let(:box) { RGame::Engine::CollisionBox.new(offset_x: 8, offset_y: 16, width: 16, height: 16) }

  def actor(x, y)
    actor_class.new(x, y, box)
  end

  def system(solid:, world_width: 1000, world_height: 1000)
    described_class.new(
      tile_collision: RGame::Engine::TileCollision.new(tile_width: 16, tile_height: 16, solid: solid),
      world_width: world_width, world_height: world_height
    )
  end

  it 'moves an actor freely when there are no solids' do
    a = actor(100.0, 100.0)
    system(solid: ->(_c, _r) { false }).move(a, 10, -5)
    expect(a.x).to eq(110.0)
    expect(a.y).to eq(95.0)
  end

  it 'resolves the collision box (not the sprite) against solids' do
    # Wall in column 8 (x 128..144). Actor origin (100, 0) → box at (108, 16, 16, 16),
    # right edge 124. Moving +10 would push the box into the wall; it snaps so the
    # box right edge rests at 128 → box_x 112 → actor.x 104.
    a = actor(100.0, 0.0)
    system(solid: ->(c, _r) { c == 8 }).move(a, 10, 0)
    expect(a.x).to eq(104.0)
  end

  it 'clamps the box within the world bounds' do
    a = actor(100.0, 100.0)
    system(solid: ->(_c, _r) { false }, world_width: 200, world_height: 200).move(a, 1000, 1000)
    expect(a.x).to eq(176.0) # box clamped to 184 (200-16) → actor 184-8
    expect(a.y).to eq(168.0) # box clamped to 184 → actor 184-16
  end
end
