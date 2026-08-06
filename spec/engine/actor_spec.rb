# frozen_string_literal: true

RSpec.describe Engine::Actor do
  let(:animation_set) do
    Engine::AnimationSet.new(
      stand: { row: 0, frames: 1, fps: 1 },
      walk_right: { row: 1, frames: 2, fps: 4 },
      walk_left: { row: 1, frames: 2, fps: 4, flip_x: true },
      walk_up: { row: 2, frames: 2, fps: 4 },
      walk_down: { row: 3, frames: 2, fps: 4 }
    )
  end

  # Free movement (no solids), generous world.
  let(:collision) do
    Engine::CollisionSystem.new(
      tile_collision: Engine::TileCollision.new(tile_width: 16, tile_height: 16, solid: ->(_c, _r) { false }),
      world_width: 10_000, world_height: 10_000
    )
  end

  def build_actor
    Engine::Actor.new(
      x: 100.0, y: 100.0, speed: 100.0, sprite_id: :hero,
      collision_box: Engine::CollisionBox.bottom_anchored(sprite_width: 16, sprite_height: 32, width: 16, height: 16),
      animator: Engine::Animator.new(animation_set),
      controller: Engine::PlayerController.new
    )
  end

  def actions(axes = {})
    Engine::Actions.new(axes: axes)
  end

  # Drive a fresh actor one step with the given intent and return its [row, col, flip].
  def face(axes)
    actor = build_actor
    actor.update(0.1, collision, actions(axes))
    actor.frame
  end

  it 'moves via the collision system at speed * dt' do
    actor = build_actor
    actor.update(0.5, collision, actions(move_x: 1.0))
    expect(actor.x).to eq(150.0)
  end

  it 'faces right when moving right (walk_right row)' do
    row, _col, flip = face(move_x: 1.0)
    expect(row).to eq(1)
    expect(flip).to be(false)
  end

  it 'faces left, flipped, when moving left' do
    row, _col, flip = face(move_x: -1.0)
    expect(row).to eq(1)
    expect(flip).to be(true)
  end

  it 'faces up when moving up' do
    expect(face(move_y: -1.0).first).to eq(2)
  end

  it 'faces down when moving down' do
    expect(face(move_y: 1.0).first).to eq(3)
  end

  it 'prefers horizontal facing over vertical on diagonals' do
    expect(face(move_x: 1.0, move_y: -1.0).first).to eq(1) # walk_right, not walk_up
  end

  it 'stands and idles with no input' do
    actor = build_actor
    actor.update(0.1, collision, actions)
    expect(actor.x).to eq(100.0)
    expect(actor.frame).to eq([0, 0, false]) # stand
  end
end
