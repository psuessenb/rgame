# frozen_string_literal: true

RSpec.describe Engine::Components::Sprite do
  subject(:sprite) { described_class.new(id: :ship, scale: 2.0, z: 3) }

  # Resolve abs coordinates by placing the node under a parent and running a phase.
  let(:node) { Engine::Node2D.new.add_node(Engine::Node2D.new(x: 5, y: 6)) }

  before do
    node.add_component(sprite)
    node.parent.control(Engine::Actions.new) # resolve node.abs_x/abs_y
  end

  describe '#draw' do
    let(:renderer) { instance_double(FakeRenderer) }

    it 'draws the image centered on the absolute origin, with no angle (the node rotates it)' do
      allow(renderer).to receive(:image)
      sprite.draw(renderer)
      # No angle argument: the Node2D rotation wrapper orients the sprite, so passing
      # one here would double-rotate. The mock's #image has no angle parameter.
      expect(renderer).to have_received(:image).with(:ship, 5, 6, scale: 2.0, z: 3)
    end
  end
end
