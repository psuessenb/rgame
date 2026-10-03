# frozen_string_literal: true

RSpec.describe RGame::Engine::Scene::Room do
  describe '.of' do
    let(:root) { RGame::Engine::Node2D.new }
    let(:room) { root.add_node(described_class.new.tap { it.scene = it }) }

    it 'is the room a node stands in, however deep' do
      node = room.add_node(RGame::Engine::Node2D.new).add_node(RGame::Engine::Node2D.new)

      expect(described_class.of(node)).to be(room)
    end

    it 'is the room itself, which is its own scene' do
      expect(described_class.of(room)).to be(room)
    end

    it 'looks past a scene inside the room that is not a room' do
      inner = room.add_node(RGame::Engine::Node2D.new.tap { it.scene = it })
      node = inner.add_node(RGame::Engine::Node2D.new)

      expect(described_class.of(node)).to be(room)
    end

    it 'is nil outside every room, and for a node in no tree' do
      outside = root.add_node(RGame::Engine::Node2D.new)

      expect([described_class.of(outside), described_class.of(RGame::Engine::Node2D.new)]).to eq([nil, nil])
    end
  end
end
