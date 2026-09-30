# frozen_string_literal: true

# A fall runs every tick it lasts, and its look with it, so neither may allocate
# once warm.
RSpec.describe RGame::Engine::Components::Fall do
  let(:parts) { RGame::Engine::Components }
  let(:dt) { 1.0 / 60 }
  let(:root) { RGame::Engine::Node2D.new }
  let(:world) { root.add_node(RGame::Engine::Node2D.new) }
  let(:node) do
    RGame::Engine::Node2D.new(x: 40.0, y: 27.0).tap do |hero|
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
