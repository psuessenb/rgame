# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::Pushable do
  def components = RGame::Engine::Components
  def dt = 1.0 / 60

  # 20 columns by 12 rows of 16 px tiles, open but for column 18, which is solid from top to
  # bottom: its left edge is at x = 288. The scene mounts both a TileWorld and a
  # CollisionWorld, so a crate meets a solid tile and a collider on the same terms.
  let(:map) { WalledTileMap.build(Array.new(12) { "#{'.' * 18}#." }) }
  let(:scene) { RGame::Engine::Node2D.new.tap { it.scene = it } }

  before do
    scene.add_component(components::TileWorld.new(map: map, tilemap_id: :level))
    scene.add_component(components::CollisionWorld.new(cell_size: 64))
    scene.enter_tree
  end

  def tick(count = 1) = count.times { scene.update(dt) }

  # 60 px/s is one pixel a step on each axis the intent names.
  def hero_at(x, y, intent: [1, 0], height: 16)
    node = RGame::Engine::Node2D.new(x:, y:)
    node.add_component(components::BoxCollider.new(width: 16, height:, layer: :hero))
    node.add_component(components::CharacterBody.new(speed: 60.0, blocked_by: %i[tiles wall crate],
                                                     pushes: [:crate]))
        .set_intent(*intent)
    scene.add_node(node)
  end

  def crate_at(x, y, height: 16, pushes: [])
    node = RGame::Engine::Node2D.new(x:, y:)
    node.add_component(components::BoxCollider.new(width: 16, height:, layer: :crate))
    node.add_component(described_class.new(blocked_by: %i[tiles wall crate hero], pushes:))
    scene.add_node(node)
  end

  def wall_at(x)
    node = RGame::Engine::Node2D.new(x:, y: 0.0)
    node.add_component(components::BoxCollider.new(width: 16, height: 400, layer: :wall))
    scene.add_node(node)
  end

  def body(node) = node.get_component(components::CharacterBody)
  def collider(node) = node.get_component(components::BoxCollider)
  def pushable(node) = node.get_component(described_class)

  def blocks_of(mover)
    reports = []
    mover.on_blocked { |by, axis| reports << [by, axis] }
    reports
  end

  describe 'a step a crate stopped' do
    it 'moves the crate by what is left of the step, and the pusher with it' do
      hero = hero_at(99.5, 100.0)
      crate = crate_at(116.0, 100.0)
      tick
      expect([hero.x, crate.x]).to eq([100.5, 116.5])
    end

    it 'moves the crate on the axis it stopped and no other' do
      hero = hero_at(100.0, 100.0, intent: [1, 1])
      crate = crate_at(116.0, 100.0)
      tick
      expect([crate.y, hero.y]).to eq([100.0, 101.0])
    end

    it 'reports nothing while the crate goes the whole way' do
      hero = hero_at(100.0, 100.0)
      crate_at(116.0, 100.0)
      reports = blocks_of(body(hero))
      tick(30)
      expect(reports).to be_empty
    end

    it 'keeps pushing for as long as the step goes on' do
      hero_at(100.0, 100.0)
      crate = crate_at(116.0, 100.0)
      tick(30)
      expect(crate.x).to be_within(1e-6).of(146.0)
    end
  end

  describe 'a crate that cannot move' do
    it 'stops against a solid tile, and holds the pusher flush against it' do
      hero = hero_at(256.0, 100.0)
      crate = crate_at(272.0, 100.0)
      tick(10)
      expect([hero.x, crate.x]).to eq([256.0, 272.0])
    end

    it 'stops against a collider, the same way' do
      wall_at(40.0)
      hero = hero_at(72.0, 100.0, intent: [-1, 0])
      crate = crate_at(56.0, 100.0)
      tick(10)
      expect([hero.x, crate.x]).to eq([72.0, 56.0])
    end

    it 'reports the crate to the pusher, once, on the axis it stopped' do
      hero = hero_at(256.0, 100.0)
      crate = crate_at(272.0, 100.0)
      reports = blocks_of(body(hero))
      tick(30)
      expect(reports).to eq([[collider(crate), :x]])
    end

    it 'reports the tile to the crate, once' do
      hero_at(256.0, 100.0)
      crate = crate_at(272.0, 100.0)
      reports = blocks_of(pushable(crate))
      tick(30)
      expect(reports).to eq([[RGame::Engine::TileBlockers::TILES, :x]])
    end

    # A crate has no step of its own, so its blockers are counted from one of its updates to
    # the next. A pusher that updates after it must not end and restart the block each tick.
    it 'reports once whether its pusher updates before it or after it' do
      crate = crate_at(272.0, 100.0)
      hero_at(256.0, 100.0)
      blocked = blocks_of(pushable(crate))
      unblocked = []
      pushable(crate).on_unblocked { unblocked << it }
      tick(30)
      expect([blocked.size, unblocked.size]).to eq([1, 0])
    end

    it 'reports the tile gone once the pusher stops' do
      hero = hero_at(256.0, 100.0)
      crate = crate_at(272.0, 100.0)
      unblocked = []
      pushable(crate).on_unblocked { unblocked << it }
      tick(10)
      body(hero).set_intent(0, 0)
      tick(2)
      expect(unblocked).to eq([RGame::Engine::TileBlockers::TILES])
    end
  end

  describe 'a crate half-way to a wall' do
    it 'moves half-way, and the pusher follows that far' do
      hero = hero_at(255.5, 100.0)
      crate = crate_at(271.5, 100.0)
      tick
      expect([hero.x, crate.x]).to eq([256.0, 272.0])
    end

    it 'stops the pusher, reporting the crate' do
      hero = hero_at(255.5, 100.0)
      crate = crate_at(271.5, 100.0)
      reports = blocks_of(body(hero))
      tick
      expect(reports).to eq([[collider(crate), :x]])
    end
  end

  describe 'pushes: of its own' do
    it 'pushes the crate behind it' do
      hero_at(100.0, 100.0)
      crates = [116.0, 132.0].map { crate_at(it, 100.0, pushes: [:crate]) }
      tick(10)
      expect(crates.map(&:x)).to eq([126.0, 142.0])
    end

    it 'moves a row of PUSH_DEPTH crates' do
      hero_at(100.0, 100.0)
      crates = Array.new(components::Mover::PUSH_DEPTH) { crate_at(116.0 + (16 * it), 100.0, pushes: [:crate]) }
      tick
      expect(crates.map(&:x)).to eq([117.0, 133.0, 149.0, 165.0])
    end

    it 'holds the pusher at a row one crate longer, as a wall would' do
      hero = hero_at(100.0, 100.0)
      crates = Array.new(components::Mover::PUSH_DEPTH + 1) { crate_at(116.0 + (16 * it), 100.0, pushes: [:crate]) }
      tick(5)
      expect([hero.x, crates.first.x, crates.last.x]).to eq([100.0, 116.0, 180.0])
    end

    it 'never pushes back the node that pushed it' do
      first = crate_at(116.0, 100.0, pushes: [:crate])
      second = crate_at(132.0, 100.0, pushes: [:crate])
      tick
      pushable(second).push(-1.0, 0.0, by: first)
      expect([first.x, second.x, pushable(second).pushed_x]).to eq([116.0, 132.0, 0.0])
    end

    it 'pushes a crate that did not push it' do
      first = crate_at(116.0, 100.0, pushes: [:crate])
      second = crate_at(132.0, 100.0, pushes: [:crate])
      tick
      pushable(second).push(-1.0, 0.0)
      expect([first.x, second.x]).to eq([115.0, 131.0])
    end
  end

  describe 'two pushers' do
    it 'move a crate side by side as far as one would, not twice as far' do
      heroes = [hero_at(100.0, 100.0), hero_at(100.0, 116.0)]
      crate = crate_at(116.0, 100.0, height: 32)
      tick(10)
      expect([crate.x, *heroes.map(&:x)]).to eq([126.0, 110.0, 110.0])
    end

    it 'hold a crate still from opposite sides, and both are stopped by it' do
      left = hero_at(100.0, 100.0)
      right = hero_at(132.0, 100.0, intent: [-1, 0])
      crate = crate_at(116.0, 100.0)
      reports = [blocks_of(body(left)), blocks_of(body(right))]
      tick(10)
      expect([left.x, crate.x, right.x, reports]).to eq(
        [100.0, 116.0, 132.0, [[[collider(crate), :x]], [[collider(crate), :x]]]]
      )
    end
  end

  describe 'what it needs at attach' do
    it 'refuses a node with no BoxCollider' do
      node = RGame::Engine::Node2D.new
      node.add_component(described_class.new(blocked_by: []))
      expect { scene.add_node(node) }.to raise_error(/needs a RGame::Engine::Components::BoxCollider/)
    end

    it 'refuses a scene with no CollisionWorld' do
      bare = RGame::Engine::Node2D.new.tap { it.scene = it }
      bare.enter_tree
      node = RGame::Engine::Node2D.new
      node.add_component(components::BoxCollider.new(width: 16, height: 16, layer: :crate))
      node.add_component(described_class.new(blocked_by: []))
      expect { bare.add_node(node) }.to raise_error(/Pushable.*CollisionWorld/)
    end
  end

  it 'allocates nothing on a step that pushes a crate into a wall' do
    hero = hero_at(256.0, 100.0)
    crate_at(272.0, 100.0)
    tick(10)
    expect { body(hero)._update(dt) }.to allocate_nothing
  end

  # Thirty-five steps take the crate from 126 to 161, inside the two broadphase cells it
  # already spans. The first collider into a new cell creates that cell's bucket, once, and
  # that is SpatialHash's cost rather than the push's.
  it 'allocates nothing on a step that pushes a crate along' do
    hero = hero_at(100.0, 100.0)
    crate_at(116.0, 100.0)
    tick(10)
    expect { body(hero)._update(dt) }.to allocate_nothing.over(30)
  end

  # The caller that uses both: a crate a hero pushes across a route a Navigator planned. The
  # route was planned over the map, and a crate is a collider rather than a solid cell, so
  # nothing replans. A walker blocked by crates waits behind it for good, and one that pushes
  # crates shoves it along the route.
  describe 'a crate pushed onto a route a Navigator planned' do
    def walker(pushes: [])
      node = RGame::Engine::Node2D.new(x: 18.0, y: 50.0)
      node.add_component(components::BoxCollider.new(width: 12, height: 12, layer: :walker))
      navigator = node.add_component(components::Navigator.new(speed: 30.0, blocked_by: %i[tiles crate],
                                                               pushes:))
      scene.add_node(node)
      navigator.go_to(200.0, 56.0)
      navigator
    end

    # The hero pushes the crate 40 px down, from above the route into the middle of it,
    # well before the walker arrives.
    def push_crate_onto_route
      hero = hero_at(80.0, 0.0, intent: [0, 1])
      crate = crate_at(80.0, 16.0)
      tick(40)
      body(hero).set_intent(0, 0)
      crate
    end

    it 'leaves a walker blocked by crates waiting behind it, reporting the crate' do
      navigator = walker
      crate = push_crate_onto_route
      reports = blocks_of(navigator)
      tick(300)
      expect([navigator.finished?, reports, navigator.node.x + 12]).to eq([false, [[collider(crate), :x]], 80.0])
    end

    it 'lets a walker that pushes crates shove it along the route' do
      navigator = walker(pushes: [:crate])
      crate = push_crate_onto_route
      tick(400)
      expect([navigator.finished?, crate.x]).to match([true, be > 180.0])
    end
  end
end
