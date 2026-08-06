# frozen_string_literal: true

RSpec.describe Engine::Components::Targeting do
  # Targeting queries the scene's CollisionWorld, so build the same arrangement the game
  # has: a scene boundary carrying the world, enemy nodes whose CircleColliders register
  # with it, and a tower node carrying the Targeting under test. A tick resolves positions
  # (control), rebuilds the broadphase index and runs the targeting (update).
  let(:scene) { Engine::Node2D.new.tap { it.scene = it } }

  before do
    scene.add_component(Engine::Components::CollisionWorld.new(cell_size: 64))
    scene.enter_tree
  end

  # An enemy at (x, y): a live node carrying a CircleCollider on the given layer.
  def enemy(x, y, layer: :enemy)
    node = Engine::Node2D.new(x: x, y: y)
    node.add_component(Engine::Components::CircleCollider.new(radius: 10, layer: layer))
    scene.add_node(node)
    node
  end

  # A tower at (x, y); returns its Targeting component.
  def tower(x, y, range: 100, **)
    node = Engine::Node2D.new(x: x, y: y)
    targeting = node.add_component(described_class.new(range: range, **))
    scene.add_node(node)
    targeting
  end

  def tick
    scene.control(Engine::Actions.new)
    scene.update(1.0 / 60)
  end

  describe 'construction' do
    it 'raises on an unknown policy' do
      expect { described_class.new(range: 100, policy: :bogus) }
        .to raise_error(ArgumentError, /unknown targeting policy/)
    end
  end

  describe '#target (policy: :nearest)' do
    it 'is the nearest enemy in range' do
      enemy(180, 100)        # 80px away
      near = enemy(140, 100) # 40px away
      targeting = tower(100, 100)
      tick
      expect(targeting.target).to be(near)
    end

    it 'is nil when no enemy is in range' do
      enemy(300, 100) # 200px away, range 100
      targeting = tower(100, 100)
      tick
      expect(targeting.target).to be_nil
    end

    it 'ignores colliders outside the targeted layer' do
      enemy(120, 100, layer: :tower) # closer, but not an enemy
      real = enemy(150, 100, layer: :enemy)
      targeting = tower(100, 100, layer: :enemy)
      tick
      expect(targeting.target).to be(real)
    end

    it 'drops a target that has been freed' do
      gone = enemy(150, 100)
      targeting = tower(100, 100)
      tick
      expect(targeting.target).to be(gone)

      gone.queue_free
      tick
      expect(targeting.target).to be_nil
    end

    it 'selects without allocating per update' do
      enemy(150, 100)
      targeting = tower(100, 100)
      tick # resolve positions + build the broadphase index
      expect { targeting.update(1.0 / 60) }.to allocate_nothing
    end
  end
end
