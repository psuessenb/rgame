# frozen_string_literal: true

# Every footing asks the floor every tick, and every mover kept on it asks how far it
# reaches, so neither may allocate with platforms over the gaps.
RSpec.describe RGame::Engine::Components::Platform do
  let(:parts) { RGame::Engine::Components }
  let(:root) do
    RGame::Engine::Node2D.new.tap do |scene|
      scene.scene = scene
      map = WalledTileMap.build(Array.new(4) { '...~~~~~~...' })
      scene.add_component(parts::TileWorld.new(map: map, tilemap_id: :map))
    end
  end
  let(:world) { root.get_component(parts::TileWorld) }

  before do
    [64.0, 100.0, 124.0].each do |x|
      node = RGame::Engine::Node2D.new(x: x, y: 24.0)
      node.add_component(parts::BoxCollider.new(width: 32, height: 16, offset_x: -16, offset_y: -8))
      node.add_component(described_class.new)
      root.add_node(node)
    end
    root.enter_tree
  end

  it 'allocates nothing asking the floor and the platform under a point' do
    expect { world.floor_at?(70.0, 24.0) || world.platform_under(90.0, 24.0) }.to allocate_nothing
  end

  # Across the ground, the first platform, the gap after it, and back again.
  it 'allocates nothing working out how far the floor reaches' do
    expect do
      world.floor_reach_x(40.0, 24.0, 60.0)
      world.floor_reach_x(130.0, 24.0, -60.0)
      world.floor_reach_y(70.0, 20.0, 30.0)
      world.floor_reach_y(70.0, 28.0, -30.0)
    end.to allocate_nothing
  end

  # A raft shuttling along the chasm's lower rows, carrying a rider kept on it by :gaps
  # and a rider with no Mover at all.
  describe 'a raft and its riders' do
    let(:raft) do
      RGame::Engine::Node2D.new.tap do |node|
        node.add_component(parts::BoxCollider.new(width: 48, height: 16, offset_x: -24, offset_y: -8))
        node.add_component(described_class.new)
        route = RGame::Engine::Path.new([[80.0, 56.0], [110.0, 56.0]])
        node.add_component(parts::PathFollow.new(path: route, speed: 30, loop: true))
        root.add_node(node)
      end
    end

    def rider(x, body:)
      RGame::Engine::Node2D.new(x: x, y: 56.0).tap do |node|
        node.add_component(parts::BoxCollider.new(width: 4, height: 4, offset_x: -2, offset_y: -2))
        node.add_component(parts::Footing.new(coyote: 1000))
        node.add_component(parts::CharacterBody.new(speed: 30, blocked_by: [:gaps])) if body
        root.add_node(node)
      end
    end

    def tick = root.update(1.0 / 60)

    before { raft }

    # Four seconds shuttle the raft there and back twice. The first carry each way fills a
    # call's caches once, 4 objects in all, so the warm-up runs four seconds too and the
    # measurement then turns round at both ends of the route again.
    it 'allocates nothing carrying its riders along a looping walk' do
      riders = [rider(76.0, body: true), rider(84.0, body: false)]
      root.enter_tree
      tick
      expect(riders.map { it.get_component(parts::Footing).platform }).to all(be(raft.get_component(described_class)))
      expect { tick }.to allocate_nothing.after_warmup(240).over(240)
    end

    it 'allocates nothing boarding and leaving' do
      node = rider(80.0, body: false)
      root.enter_tree
      board_and_leave = lambda do
        node.x = raft.x
        tick
        node.x = 20.0
        tick
      end
      2.times { board_and_leave.call }
      expect { board_and_leave.call }.to allocate_nothing
    end
  end
end
