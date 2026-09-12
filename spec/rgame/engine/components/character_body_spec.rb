# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::CharacterBody do
  # Unit scope: the body turns a movement intent into a step, and `blocked_by:` decides
  # where that step is allowed to land. Both halves are here because they are one class
  # now — an unblocked body writes to the node, a `:tiles` body hands itself to the
  # scene's TileWorld as an actor. The tile-vs-box maths itself is tile_collision_spec's.
  let(:node) { RGame::Engine::Node2D.new(x: 100.0, y: 100.0) }

  # Node2D#system walks the scene and the root, neither of which a bare node has, so the
  # scene's mounted systems are stubbed by class. A block rather than `with(...)` because
  # BoxCollider#on_attach asks for a CollisionWorld on the same node.
  def mount(systems)
    allow(node).to receive(:system) { |klass| systems[klass] }
  end

  def tile_world = instance_double(RGame::Engine::Components::TileWorld, move: nil)

  describe 'an unblocked body — the default' do
    let(:body) { described_class.new(speed: 50.0) }

    before do
      node.add_component(body)
      node.enter_tree
    end

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

    # The three things an actor with nothing to bump into must not need: a sprite to be
    # sized by, a collider to carry a shape, and a system on the scene to resolve
    # against. This node has none of them — a bare Node2D with one component — and that
    # is what `blocked_by: []` buys.
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

      it 'moves with no collider on the node' do
        expect(node.get_component(RGame::Engine::Components::BoxCollider)).to be_nil
        body.set_intent(1.0, 0.0)
        expect { body.update(0.1) }.to change(node, :x).by(5.0)
      end
    end
  end

  describe 'blocked_by: [:tiles]' do
    let(:world)    { tile_world }
    let(:collider) { RGame::Engine::Components::BoxCollider.new(width: 16, height: 16, offset_x: 8, offset_y: 16) }
    let(:body)     { described_class.new(speed: 50.0, blocked_by: [:tiles]) }

    before do
      mount(RGame::Engine::Components::TileWorld => world)
      node.add_component(collider)
      node.add_component(body)
      node.enter_tree
    end

    it 'resolves the step through the tile world instead of writing to the node' do
      body.set_intent(1.0, 0.0)
      body.update(0.5)
      expect(world).to have_received(:move).with(body, 25.0, 0.0) # 1.0 * 50 * 0.5
    end

    it 'leaves the node where it was — the world writes the resolved position back' do
      body.set_intent(1.0, 0.0)
      body.update(0.5)
      expect([node.x, node.y]).to eq([100.0, 100.0])
    end

    it 'does nothing when the intent is zero' do
      body.set_intent(0.0, 0.0)
      body.update(0.5)
      expect(world).not_to have_received(:move)
    end

    it 'takes a bare symbol as readily as a list' do
      bare = RGame::Engine::Node2D.new
      allow(bare).to receive(:system) { |klass| klass == RGame::Engine::Components::TileWorld ? world : nil }
      bare.add_component(RGame::Engine::Components::BoxCollider.new(width: 4, height: 4))
      bare.add_component(described_class.new(speed: 50.0, blocked_by: :tiles))
      expect { bare.enter_tree }.not_to raise_error
    end

    describe 'the actor adapter CollisionSystem#move drives' do
      it 'reads x/y from the node' do
        expect([body.x, body.y]).to eq([100.0, 100.0])
      end

      it 'writes a resolved position back to the node' do
        body.x = 140.0
        body.y = 160.0
        expect([node.x, node.y]).to eq([140.0, 160.0])
      end

      it 'resolves with the sibling collider’s box, not one of its own' do
        expect(body.collision_box).to be(collider.box)
      end

      # The shape has one owner, so retuning it retunes both what stops a step and what
      # reports a contact. Under the old two-component arrangement these were two boxes
      # and this assignment moved only one of them.
      it 'follows a box reassigned on the collider' do
        retuned = RGame::Engine::CollisionBox.new(width: 4, height: 4, offset_x: 1, offset_y: 2)
        collider.box = retuned
        expect(body.collision_box).to be(retuned)
      end
    end
  end

  # A body that cannot be blocked the way it was told to says so at attach, rather than
  # falling back to free movement: an actor walking through walls looks like a collision
  # bug, and the cause would be a scene three files away.
  describe 'what it refuses at attach' do
    it 'refuses :tiles on a scene with no TileWorld, naming both' do
      mount({})
      node.add_component(RGame::Engine::Components::BoxCollider.new(width: 4, height: 4))
      node.add_component(described_class.new(speed: 50.0, blocked_by: [:tiles]))
      expect { node.enter_tree }.to raise_error(/blocked_by :tiles.*no TileWorld/m)
    end

    it 'refuses :tiles on a node with no collider to resolve' do
      mount(RGame::Engine::Components::TileWorld => tile_world)
      node.add_component(described_class.new(speed: 50.0, blocked_by: [:tiles]))
      expect { node.enter_tree }.to raise_error(/needs a RGame::Engine::Components::BoxCollider/)
    end

    # Actor-versus-actor blocking is not built: a layer name is refused rather than
    # accepted and quietly ignored, which would be the silent failure this component's
    # raises exist to avoid.
    it 'refuses a collider layer, since :tiles is the only blocker there is' do
      mount(RGame::Engine::Components::TileWorld => tile_world)
      node.add_component(RGame::Engine::Components::BoxCollider.new(width: 4, height: 4))
      node.add_component(described_class.new(speed: 50.0, blocked_by: %i[tiles npc]))
      expect { node.enter_tree }.to raise_error(/blocked_by :npc.*only/m)
    end
  end
end
