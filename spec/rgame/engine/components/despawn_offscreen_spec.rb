# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::DespawnOffscreen do
  subject(:despawn) { described_class.new(width: 100, height: 80, margin: 5) }

  let(:node) { RGame::Engine::Node2D.new }

  before { node.add_component(despawn) }

  describe '#update' do
    it 'queues the node for removal once it is fully past an edge' do
      node.x = 106
      despawn.update(0.0)
      expect(node).to be_freed
    end

    it 'leaves a node inside the bounds (plus margin) alive' do
      node.x = -5
      node.y = 85
      despawn.update(0.0)
      expect(node).not_to be_freed
    end
  end
end
