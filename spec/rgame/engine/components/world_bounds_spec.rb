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
end
