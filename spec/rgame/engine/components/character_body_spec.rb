# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::CharacterBody do
  # Unit scope: the base body turns a movement intent into a plain move at its speed,
  # with no collision world and no sprite behind it — the case for an actor in a world
  # with nothing to bump into. TileCharacterBody's spec covers the collision-checked
  # subclass; between them they pin the seam (`apply_move`) from both sides.
  let(:node) { RGame::Engine::Node2D.new(x: 100.0, y: 100.0) }
  let(:body) { described_class.new(speed: 50.0) }

  before do
    node.add_component(body)
    node.enter_tree
  end

  describe '#update' do
    it 'moves the node by the intent scaled by speed and dt' do
      body.set_intent(1.0, -0.5)
      body.update(0.5)
      expect([node.x, node.y]).to eq([125.0, 87.5]) # 1.0 * 50 * 0.5, -0.5 * 50 * 0.5
    end

    it 'does nothing when the intent is zero' do
      body.set_intent(0.0, 0.0)
      body.update(0.5)
      expect([node.x, node.y]).to eq([100.0, 100.0])
    end

    it 'exposes the intent as the facing for the animator' do
      body.set_intent(-1.0, 1.0)
      expect([body.move_x, body.move_y]).to eq([-1.0, 1.0])
    end
  end

  # The two things a plain actor must not need: a sprite to be sized by, and a system on
  # the scene to resolve against. This node has neither — it is a bare Node2D on a scene
  # with nothing mounted — and that is the whole reason the intent lives here rather than
  # in the tile-bound subclass.
  describe 'what it does not need' do
    it 'moves with no sprite size on the node' do
      expect(node.width).to be_zero
      body.set_intent(1.0, 0.0)
      expect { body.update(0.1) }.to change(node, :x).by(5.0)
    end

    it 'moves with no world system on the scene' do
      expect(node.system(RGame::Engine::Components::TileWorld)).to be_nil
      body.set_intent(0.0, 1.0)
      expect { body.update(0.1) }.to change(node, :y).by(5.0)
    end
  end
end
