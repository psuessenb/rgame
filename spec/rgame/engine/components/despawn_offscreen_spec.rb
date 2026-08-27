# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::DespawnOffscreen do
  let(:node) { RGame::Engine::Node2D.new }

  describe '#update' do
    subject(:despawn) { described_class.new(width: 100, height: 80, margin: 5) }

    before do
      node.add_component(despawn)
      node.enter_tree # bounds are resolved at attach, so the node has to be live
    end

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

  describe 'bounds resolution' do
    subject(:despawn) { described_class.new(margin: 5) }

    it 'takes the world system bounds when none were passed' do
      node.add_component(RGame::Engine::Components::World.new(width: 100, height: 80))
      node.add_component(despawn)
      node.enter_tree

      node.x = 106
      despawn.update(0.0)
      expect(node).to be_freed
    end

    it 'refuses to attach where nothing answers for the world size' do
      node.add_component(despawn)

      expect { node.enter_tree }.to raise_error(RuntimeError, /no world bounds in scope/)
    end
  end
end
