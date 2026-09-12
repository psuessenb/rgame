# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::WorldBounds do
  # The contract has to be answerable by more than one class or naming it buys
  # nothing. TileWorld is the other implementation, and it is what lets the
  # bounds-consuming components work unchanged in a tile-map scene.
  it 'is answered by TileWorld as well as by World' do
    expect(RGame::Engine::Components::TileWorld.include?(described_class)).to be(true)
  end

  it 'raises rather than answering nil when an includer defines neither dimension' do
    incomplete = Class.new { include RGame::Engine::Components::WorldBounds }.new

    expect { incomplete.world_width }.to raise_error(NotImplementedError)
    expect { incomplete.world_height }.to raise_error(NotImplementedError)
  end

  describe '.resolve' do
    let(:node) { RGame::Engine::Node2D.new }

    it 'returns explicit bounds without consulting the tree at all' do
      # Nothing is mounted, and yet no error: an explicit pair short-circuits the lookup.
      expect(described_class.resolve(node, 100, 80)).to eq([100, 80])
    end

    it 'falls back to the world system for a dimension left nil' do
      node.add_component(RGame::Engine::Components::World.new(width: 640, height: 480))

      expect(described_class.resolve(node, nil, nil)).to eq([640, 480])
      expect(described_class.resolve(node, 100, nil)).to eq([100, 480])
    end

    it 'raises when nothing in scope answers the contract' do
      expect { described_class.resolve(node, nil, nil) }
        .to raise_error(RuntimeError, /no world bounds in scope/)
    end
  end

  # A node gets one answer to "what happens at the edge of the world". Every pair is
  # refused, in both add orders, whether the node is assembled before it enters the tree
  # (every component present when the first attaches) or grown while live (each attaches
  # on arrival) — the two lifecycles that make an attach-time check order-dependent if it
  # is done wrong.
  describe '.one_response!' do
    let(:scene) do
      RGame::Engine::Node2D.new.tap do |root|
        root.scene = root
        root.add_component(RGame::Engine::Components::World.new(width: 200, height: 100))
      end
    end
    let(:node) { RGame::Engine::Node2D.new }

    def build_response(name)
      case name
      when 'ScreenWrap' then [RGame::Engine::Components::ScreenWrap.new]
      when 'DespawnOffscreen' then [RGame::Engine::Components::DespawnOffscreen.new]
      else [RGame::Engine::Components::BoxCollider.new(width: 10, height: 10),
            RGame::Engine::Components::Velocity.new(blocked_by: [:bounds])]
      end
    end

    def assembled(*component_lists)
      component_lists.flatten.each { node.add_component(it) }
      scene.add_node(node)
      -> { scene.enter_tree }
    end

    def grown(*component_lists)
      scene.add_node(node)
      scene.enter_tree
      -> { component_lists.flatten.each { node.add_component(it) } }
    end

    ['ScreenWrap', 'DespawnOffscreen', 'Velocity (blocked_by :bounds)'].permutation(2).each do |pair|
      describe "#{pair.first}, then #{pair.last}", pair: pair do
        def first_name = self.class.metadata[:pair].first
        def second_name = self.class.metadata[:pair].last

        it 'raises at attach when the node is assembled before entering the tree' do
          attach = assembled(build_response(first_name), build_response(second_name))
          expect(&attach).to raise_error(RuntimeError, /two responses to the edge of the world/)
        end

        it 'raises at attach when the second is added to a live node, naming both' do
          attach = grown(build_response(first_name), build_response(second_name))
          named = /#{Regexp.escape(first_name)} and #{Regexp.escape(second_name)}/
          expect(&attach).to raise_error(RuntimeError, named)
        end
      end
    end

    # Every caller in the repository has this shape: something that moves the node, and
    # one response to the edge.
    it 'accepts a mover that does not declare :bounds beside a ScreenWrap' do
      attach = assembled(RGame::Engine::Components::Velocity.new(vx: 10.0),
                         RGame::Engine::Components::ScreenWrap.new)
      expect(&attach).not_to raise_error
    end

    it 'does not refuse a pooled node its own response when it enters again' do
      node.add_component(RGame::Engine::Components::DespawnOffscreen.new)
      scene.add_node(node)
      scene.enter_tree
      scene.remove_node(node)
      expect { scene.add_node(node) }.not_to raise_error
    end

    # A pooled node attaches on every spawn, and a spawn can be on any frame.
    it 'allocates nothing' do
      node.add_component(RGame::Engine::Components::Velocity.new(vx: 10.0))
      node.add_component(RGame::Engine::Components::ScreenWrap.new)
      expect { described_class.one_response!(node) }.to allocate_nothing
    end
  end
end
