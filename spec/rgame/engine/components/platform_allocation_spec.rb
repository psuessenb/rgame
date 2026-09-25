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
end
