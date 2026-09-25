# frozen_string_literal: true

RSpec.describe RGame::Engine::GapBlockers do
  # A gap two cells square, at x 32..64 and y 16..48, and a solid tile at x 80..96, y 16..32.
  # Every step goes through a CollisionSystem holding the map's gaps and its solid tiles, as
  # a mover declaring `blocked_by: %i[tiles gaps]` builds one. The box is 12x6 with no
  # offset, so its centre is (x + 6, y + 3).
  let(:world) do
    RGame::Engine::Components::TileWorld.new(
      map: WalledTileMap.build(['......', '..~~.#', '..~~..', '......']), tilemap_id: :map
    )
  end
  let(:system) { RGame::Engine::CollisionSystem.new(blockers: [world.gap_blockers, world.blockers]) }
  let(:actor_class) { Struct.new(:x, :y, :collision_box) }

  def step(x, y, dx, dy)
    actor = actor_class.new(x, y, RGame::Engine::CollisionBox.new(width: 12, height: 6))
    system.move(actor, dx, dy)
    actor
  end

  def centre_on_floor?(actor) = world.floor_at?(actor.x + 6, actor.y + 3)

  it 'is the source a TileWorld hands every mover on its map' do
    expect(world.gap_blockers).to be(world.gap_blockers).and be_a(described_class)
  end

  describe 'a step toward a gap' do
    it 'stops moving right with the centre on the last of the floor' do
      actor = step(10.0, 30.0, 20.0, 0.0)
      expect([actor.x, centre_on_floor?(actor)]).to match([be_within(1e-6).of(26.0), true])
    end

    it 'stops moving left with the centre on the last of the floor' do
      actor = step(70.0, 30.0, -20.0, 0.0)
      expect([actor.x, centre_on_floor?(actor)]).to match([be_within(1e-6).of(58.0), true])
    end

    it 'stops moving down with the centre on the last of the floor' do
      actor = step(40.0, 0.0, 0.0, 20.0)
      expect([actor.y, centre_on_floor?(actor)]).to match([be_within(1e-6).of(13.0), true])
    end

    it 'says the gaps stopped it' do
      step(10.0, 30.0, 20.0, 0.0)
      expect([system.blocked_x, system.blocked_x.layer, system.blocked_x.node])
        .to eq([described_class::GAPS, :gaps, nil])
    end
  end

  it 'leaves a step along the edge of a gap alone' do
    actor = step(10.0, 9.0, 30.0, 0.0)
    expect([actor.x, system.blocked_x]).to eq([40.0, nil])
  end

  it 'keeps the free axis of a diagonal step into a gap, as a wall does' do
    actor = step(10.0, 30.0, 20.0, 4.0)
    expect([actor.x, actor.y]).to match([be_within(1e-6).of(26.0), 34.0])
  end

  it 'leaves a step that starts off the floor alone' do
    actor = step(40.0, 30.0, 10.0, 0.0)
    expect([actor.x, system.blocked_x]).to eq([50.0, nil])
  end

  describe 'beside the solid tiles' do
    it 'loses to a wall nearer than any gap' do
      actor = step(66.0, 20.0, 10.0, 0.0)
      expect([actor.x, system.blocked_x.layer]).to eq([68.0, :tiles])
    end

    it 'wins over a wall when the gap is nearer' do
      actor = step(66.0, 20.0, -10.0, 0.0)
      expect([actor.x, system.blocked_x.layer]).to match([be_within(1e-6).of(58.0), :gaps])
    end
  end
end
