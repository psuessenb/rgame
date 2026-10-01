# frozen_string_literal: true

# A fall runs every tick it lasts, and its look with it, so neither may allocate
# once warm.
RSpec.describe RGame::Engine::Components::Fall do
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
      hero.add_component(parts::Footing.new(coyote: 0.05))
      hero.add_component(described_class.new(duration: 0.25))
      hero.add_component(parts::Shrink.new)
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

  # A Footing drops the node into the gap at x 64..80. The first fall adds the
  # clock to the parent's lists, which may grow them. From the second on, every
  # list already has room.
  it 'allocates nothing over a whole fall from a Footing, from the drop to the node freed' do
    2.times do
      node.x = 70.0
      world.add_node(node)
      30.times { tick }
    end
    node.x = 70.0
    world.add_node(node)

    expect { 30.times { tick } }.to allocate_nothing
  end

  it 'allocates nothing over a fall from a Footing that ends in a respawn and a blink' do
    blink = node.add_component(parts::Blink.new)
    node.add_component(parts::Respawn.new).on_respawned { blink.start(0.5) }
    fall_and_blink = lambda do
      node.x = 70.0
      60.times { tick }
    end
    2.times { fall_and_blink.call }

    expect { fall_and_blink.call }.to allocate_nothing
  end

  # Each call starts a fall and runs it whole, so every measured call has one.
  # The first fall adds the clock to the parent's lists, which may grow them.
  it 'allocates nothing over a fall started by hand, from its start to the respawn and its blink' do
    blink = node.add_component(parts::Blink.new)
    node.add_component(parts::Respawn.new).on_respawned { blink.start(0.5) }
    fall = node.get_component(described_class)
    fall_and_blink = lambda do
      fall.start
      60.times { tick }
    end
    2.times { fall_and_blink.call }

    expect { fall_and_blink.call }.to allocate_nothing
  end
end
