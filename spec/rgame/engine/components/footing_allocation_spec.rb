# frozen_string_literal: true

# A footing checks every tick for every node that has one, so it may not
# allocate once warm. The fall it starts is fall_allocation_spec's.
RSpec.describe RGame::Engine::Components::Footing do
  let(:parts) { RGame::Engine::Components }
  let(:dt) { 1.0 / 60 }
  let(:root) do
    RGame::Engine::Node2D.new.tap do |scene|
      scene.scene = scene
      map = WalledTileMap.build(['........', '....~...', '........'])
      scene.add_component(parts::TileWorld.new(map: map, tilemap_id: :map))
    end
  end
  let(:world) { root.add_node(RGame::Engine::Node2D.new) }
  let(:node) do
    RGame::Engine::Node2D.new(x: 40.0, y: 27.0).tap do |hero|
      hero.add_component(parts::FeetCollider.new(width: 12, height: 6))
      hero.add_component(parts::Hop.new(peak: 10, duration: 100, action: nil))
      hero.add_component(described_class.new(coyote: 0.05))
    end
  end

  def tick
    root.update(dt)
    root.sweep_freed
  end

  before do
    world.add_node(node)
    root.enter_tree
  end

  it 'allocates nothing checking a node on the floor' do
    tick

    expect { tick }.to allocate_nothing
  end

  it 'allocates nothing counting coyote time off the floor' do
    node.get_component(described_class).coyote = 1000.0
    tick
    node.x = 70.0
    tick

    expect { tick }.to allocate_nothing
  end

  it 'allocates nothing checking a node in the air' do
    node.get_component(parts::Hop).jump
    tick

    expect { tick }.to allocate_nothing
  end

  # Over the gap with no Fall, it looks for one every update.
  it 'allocates nothing over a gap with no Fall to start' do
    node.x = 70.0
    5.times { tick }

    expect { tick }.to allocate_nothing
  end
end
