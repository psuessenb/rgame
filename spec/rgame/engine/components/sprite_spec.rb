# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::Sprite do
  subject(:sprite) { described_class.new(id: :ship, scale: 2.0, z: 3) }

  # Resolve abs coordinates by placing the node under a parent and running a phase.
  let(:node) { RGame::Engine::Node2D.new.add_node(RGame::Engine::Node2D.new(x: 5, y: 6)) }

  before do
    node.add_component(sprite)
    node.parent.update(0.0) # resolve node.world_x/world_y (only `update` resolves the transform)
  end

  describe '#draw' do
    let(:renderer) { instance_double(FakeRenderer) }

    it 'draws the image at its own origin, with no angle (the node places and rotates it)' do
      allow(renderer).to receive(:image)
      sprite.draw(renderer, screen_view)
      # Neither a position nor an angle: Node2D#draw has already pushed this node's
      # transform, so (0, 0) *is* the node, correctly rotated. Passing either would
      # apply it a second time. The node is at (5, 6) and draws at (0, 0).
      expect(renderer).to have_received(:image).with(:ship, 0, 0, scale: 2.0, z: 3)
    end
  end
end
