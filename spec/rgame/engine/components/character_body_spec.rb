# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::CharacterBody do
  # Unit scope: the body turns a movement intent into a collision-checked move and
  # delegates the actual resolution to the TileWorld. The real tile-vs-box maths is
  # covered by tile_collision_spec / the beach integration spec, so here we use a
  # TileWorld double and assert the delegation, the node-backed actor adapter, and the
  # feet box derived from the node's dimensions.
  let(:node)  { RGame::Engine::Node2D.new(x: 100.0, y: 100.0, width: 32, height: 32) }
  let(:world) { instance_double(RGame::Engine::Components::TileWorld, move: nil) }
  let(:body)  { described_class.new(feet_width: 16, feet_height: 16, speed: 50.0) }

  before do
    allow(node).to receive(:system).with(RGame::Engine::Components::TileWorld).and_return(world)
    node.add_component(body)
    node.enter_tree # on_attach caches the world
  end

  describe '#update' do
    it 'moves the intent scaled by speed and dt through the tile world' do
      body.set_intent(1.0, 0.0)
      body.update(0.5)
      expect(world).to have_received(:move).with(body, 25.0, 0.0) # 1.0 * 50 * 0.5
    end

    it 'does nothing when the intent is zero' do
      body.set_intent(0.0, 0.0)
      body.update(0.5)
      expect(world).not_to have_received(:move)
    end

    it 'exposes the intent as the facing for the animator' do
      body.set_intent(-1.0, 1.0)
      expect([body.move_x, body.move_y]).to eq([-1.0, 1.0])
    end
  end

  describe '#collision_box' do
    it 'builds a feet box from the node dimensions, centred and bottom-anchored' do
      box = body.collision_box
      # 32x32 node, 16x16 feet → offset_x (32-16)/2 = 8, offset_y 32-16 = 16
      expect([box.offset_x, box.offset_y, box.width, box.height]).to eq([8, 16, 16, 16])
    end
  end

  describe 'the actor adapter the collision system drives' do
    it 'reads x/y from the node' do
      expect([body.x, body.y]).to eq([100.0, 100.0])
    end

    it 'writes a resolved position back to the node' do
      body.x = 140.0
      body.y = 160.0
      expect([node.x, node.y]).to eq([140.0, 160.0])
    end
  end
end
