# frozen_string_literal: true

# A footing checks every tick for every node that has one, and a fall runs every
# tick it lasts, so neither may allocate once warm.
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
      hero.add_component(described_class.new(coyote: 0.05, fall: 0.25))
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

  # The first fall adds the Fall to the parent's lists, which may grow them. From
  # the second on, every list already has room.
  it 'allocates nothing over a whole fall, from the drop to the node freed' do
    2.times do
      node.x = 70.0
      world.add_node(node)
      30.times { tick }
    end
    node.x = 70.0
    world.add_node(node)

    expect { 30.times { tick } }.to allocate_nothing
  end

  it 'allocates nothing over a fall that ends in a respawn and its flash' do
    node.add_component(parts::Respawn.new(flash: 0.5))
    fall_and_flash = lambda do
      node.x = 70.0
      60.times { tick }
    end
    2.times { fall_and_flash.call }

    expect { fall_and_flash.call }.to allocate_nothing
  end
end
