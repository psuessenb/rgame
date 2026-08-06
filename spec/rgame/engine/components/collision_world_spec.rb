# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::CollisionWorld do
  # The world is a system on the scene node; colliders on child nodes register with
  # it through their tree lifecycle. Place colliders, resolve positions with a
  # phase, then tick the world and inspect the hits each collider was told about.
  let(:scene) { RGame::Engine::Node2D.new.tap { it.scene = it } }
  let(:hits)  { [] }

  let!(:world) { scene.add_component(described_class.new(cell_size: 64)) }

  before { scene.enter_tree }

  def place(x, y, layer)
    node = RGame::Engine::Node2D.new(x: x, y: y)
    collider = node.add_component(RGame::Engine::Components::CircleCollider.new(radius: 12, layer: layer))
    collider.on_hit { |other| hits << [layer, other.layer] }
    scene.add_node(node) # scene is live, so on_attach registers the collider
    collider
  end

  def tick
    scene.control(RGame::Engine::Actions.new) # resolve absolute positions
    world.update(0.0)
  end

  describe '#update' do
    it 'reports an overlapping pair to both colliders' do
      place(100, 100, :bullet)
      place(108, 100, :rock)
      tick
      expect(hits).to contain_exactly(%i[bullet rock], %i[rock bullet])
    end

    it 'does not report colliders that are far apart' do
      place(100, 100, :bullet)
      place(400, 400, :rock)
      tick
      expect(hits).to be_empty
    end

    it 'skips colliders whose node is queued for removal' do
      place(100, 100, :bullet)
      place(108, 100, :rock).node.queue_free
      tick
      expect(hits).to be_empty
    end
  end

  describe '#unregister' do
    it 'stops a collider from being reported' do
      place(100, 100, :bullet)
      world.unregister(place(108, 100, :rock))
      tick
      expect(hits).to be_empty
    end
  end

  # query_circle / nearest read the index #update builds, so populate it with a tick
  # before querying. Distances are centre-to-centre (the collider radii don't widen it).
  describe '#query_circle' do
    def in_circle(x, y, r)
      found = []
      world.query_circle(x, y, r) { |collider| found << collider }
      found
    end

    it 'yields colliders whose centre is within the radius' do
      near = place(100, 100, :enemy)
      place(400, 400, :enemy) # outside
      tick
      expect(in_circle(100, 100, 50)).to eq([near])
    end

    it 'excludes a collider just beyond the radius' do
      place(100, 100, :enemy) # 30px away from the query point below
      tick
      expect(in_circle(130, 100, 20)).to be_empty
    end

    it 'skips a collider whose node is queued for removal' do
      place(100, 100, :enemy).node.queue_free
      tick
      expect(in_circle(100, 100, 50)).to be_empty
    end

    it 'yields nothing before the first update has built the index' do
      place(100, 100, :enemy)
      scene.control(RGame::Engine::Actions.new) # resolves positions but does not run the world
      expect(in_circle(100, 100, 50)).to be_empty
    end
  end

  describe '#nearest' do
    it 'returns the closest collider within range' do
      place(100, 100, :enemy)
      closer = place(120, 100, :enemy)
      tick
      expect(world.nearest(130, 100, 100)).to be(closer)
    end

    it 'returns nil when nothing is in range' do
      place(100, 100, :enemy)
      tick
      expect(world.nearest(400, 400, 50)).to be_nil
    end

    it 'restricts to a layer when one is given' do
      place(100, 100, :tower) # nearer, wrong layer
      enemy = place(140, 100, :enemy)
      tick
      expect(world.nearest(100, 100, 100, layer: :enemy)).to be(enemy)
    end

    it 'ignores a collider queued for removal' do
      place(100, 100, :enemy).node.queue_free
      tick
      expect(world.nearest(100, 100, 50)).to be_nil
    end

    # Targeting calls this every update, so the lookup itself must not allocate.
    it 'allocates nothing per lookup' do
      place(100, 100, :enemy)
      place(140, 100, :enemy)
      tick
      expect { world.nearest(120, 100, 100, layer: :enemy) }.to allocate_nothing
    end
  end
end
