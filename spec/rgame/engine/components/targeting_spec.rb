# frozen_string_literal: true

# What a turret may aim at: a component of the game's own, with nothing in it. Targeting
# matches it by `is_a?`, so a real class stands in rather than a double.
class SpecHostile < RGame::Engine::Component; end

# A kind of hostile, so a Targeting asking for the base class finds it too.
class SpecBoss < SpecHostile; end

RSpec.describe RGame::Engine::Components::Targeting do
  # Targeting queries the scene's CollisionWorld, so build the same arrangement the game
  # has: a scene boundary carrying the world, enemy nodes whose CircleColliders register
  # with it, and a turret node carrying the Targeting under test. A tick resolves positions
  # (control), rebuilds the broadphase index and runs the targeting (update).
  let(:scene) { RGame::Engine::Node2D.new.tap { it.scene = it } }

  before do
    scene.add_component(RGame::Engine::Components::CollisionWorld.new(cell_size: 64))
    scene.enter_tree
  end

  def circle(layer = :enemy) = RGame::Engine::Components::CircleCollider.new(radius: 10, layer:)

  # A node at (x, y) holding a CircleCollider, and each of `components`.
  def node_at(x, y, *components)
    node = RGame::Engine::Node2D.new(x: x, y: y)
    components.each { node.add_component(it) }
    scene.add_node(node)
    node
  end

  # An enemy at (x, y): a collider, and the SpecHostile a turret aims at.
  def enemy(x, y) = node_at(x, y, circle, SpecHostile.new)

  # A turret at (x, y); returns its Targeting component. `own` are components the turret
  # itself holds.
  def turret(x, y, *own, range: 100, having: SpecHostile)
    targeting = described_class.new(range:, having:)
    node_at(x, y, *own, targeting)
    targeting
  end

  def tick
    scene.control(RGame::Engine::Actions.new)
    scene.update(1.0 / 60)
  end

  describe 'construction' do
    it 'raises on an unknown policy' do
      expect { described_class.new(range: 100, having: SpecHostile, policy: :bogus) }
        .to raise_error(ArgumentError, /unknown targeting policy/)
    end

    it 'requires having:' do
      expect { described_class.new(range: 100) }.to raise_error(ArgumentError, /having/)
    end

    it 'raises for a having: that is not a Module' do
      expect { described_class.new(range: 100, having: :enemy) }
        .to raise_error(ArgumentError, /having is the component class a target holds, not :enemy/)
    end

    it 'takes no layer:, which says what a node collides as rather than what it offers' do
      expect { described_class.new(range: 100, having: SpecHostile, layer: :enemy) }
        .to raise_error(ArgumentError, /unknown keyword: :layer/)
    end
  end

  describe '#target (policy: :nearest)' do
    it 'is the nearest enemy in range' do
      enemy(180, 100)        # 80px away
      near = enemy(140, 100) # 40px away
      targeting = turret(100, 100)
      tick
      expect(targeting.target).to be(near)
    end

    it 'is nil when no enemy is in range' do
      enemy(300, 100) # 200px away, range 100
      targeting = turret(100, 100)
      tick
      expect(targeting.target).to be_nil
    end

    it 'passes over a nearer node that holds no having:, whatever its layer' do
      node_at(120, 100, circle(:enemy)) # closer, on the enemies' layer, but no SpecHostile
      real = enemy(150, 100)
      targeting = turret(100, 100)
      tick
      expect(targeting.target).to be(real)
    end

    it 'drops a target that has been freed' do
      gone = enemy(150, 100)
      targeting = turret(100, 100)
      tick
      expect(targeting.target).to be(gone)

      gone.queue_free
      tick
      expect(targeting.target).to be_nil
    end
  end

  describe 'having:, matched by is_a?' do
    it 'finds a subclass of the class it names' do
      boss = node_at(150, 100, circle, SpecBoss.new)
      targeting = turret(100, 100)
      tick
      expect(targeting.target).to be(boss)
    end

    it 'finds every node holding a module it names' do
      plain = node_at(150, 100, circle(:scenery))
      targeting = turret(100, 100, having: RGame::Engine::Components::Collider)
      tick
      expect(targeting.target).to be(plain)
    end

    it 'counts a node holding two matches as one candidate, not a raise' do
      twice = node_at(150, 100, circle, SpecHostile.new, SpecBoss.new)
      targeting = turret(100, 100)
      tick
      expect(targeting.target).to be(twice)
    end
  end

  describe 'its own node' do
    it 'is never the target, though it holds having: and is nearest' do
      other = enemy(150, 100)
      targeting = turret(100, 100, circle, SpecHostile.new)
      tick
      expect(targeting.target).to be(other)
    end

    it 'leaves nil when nothing else is in range' do
      targeting = turret(100, 100, circle, SpecHostile.new)
      tick
      expect(targeting.target).to be_nil
    end
  end

  # Reaches each filter: the turret's own collider, a nearer node without SpecHostile,
  # and the enemy that is picked.
  it 'selects without allocating per update' do
    node_at(120, 100, circle)
    enemy(150, 100)
    targeting = turret(100, 100, circle, SpecHostile.new)
    tick # resolve positions + build the broadphase index
    expect { targeting._update(1.0 / 60) }.to allocate_nothing
  end
end
