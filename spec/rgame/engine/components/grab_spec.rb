# frozen_string_literal: true

# rubocop:disable RSpec/MultipleMemoizedHelpers -- two players, their registry, the backend
# and the map are what a split-screen drag needs, and naming each is what lets the examples
# read as the rules.
RSpec.describe RGame::Engine::Components::Grab do
  def components = RGame::Engine::Components
  def dt = 1.0 / 60

  # The pushable_spec map: 20 columns of 16 px tiles, column 18 solid, its left edge at
  # x = 288. A tick runs in a game's order — poll, control, update — so a grab set in
  # `_control` is in hand for the step that follows.
  let(:controls) { RGame::Util::Controls }
  let(:map) { WalledTileMap.build(Array.new(12) { "#{'.' * 18}#." }) }
  let(:scene) { RGame::Engine::Node2D.new.tap { it.scene = it } }
  let(:backend) { FakeInputBackend.new }
  let(:one) { RGame::Engine::Player.new(id: 0, device: controls::KEYBOARD) }
  let(:two) { RGame::Engine::Player.new(id: 1, device: controls.gamepad(0)) }
  let(:players) { RGame::Engine::Players.new([one, two]) }

  before do
    scene.add_component(components::TileWorld.new(map: map, tilemap_id: :level))
    scene.add_component(components::CollisionWorld.new(cell_size: 64))
    scene.enter_tree
  end

  def tick(count = 1)
    count.times do
      players.poll(backend, dt)
      scene.control(players)
      scene.update(dt)
    end
  end

  # 60 px/s is a pixel a step. The node's origin is its box's top-left, which is what
  # Targeting measures range from: a crate flush beside it has its centre 25.3 px away.
  def hero_at(x, y, player: one, blocked_by: %i[tiles wall crate])
    node = RGame::Engine::Node2D.new(x:, y:)
    node.input_owner = player
    node.add_component(components::BoxCollider.new(width: 16, height: 16, layer: :hero))
    node.add_component(components::CharacterBody.new(speed: 60.0, blocked_by:))
    node.add_component(described_class.new(layer: :crate, range: 32))
    scene.add_node(node)
  end

  def crate_at(x, y, pushable: true)
    node = RGame::Engine::Node2D.new(x:, y:)
    node.add_component(components::BoxCollider.new(width: 16, height: 16, layer: :crate))
    node.add_component(components::Pushable.new(blocked_by: %i[tiles wall crate hero])) if pushable
    scene.add_node(node)
  end

  def wall_at(x, y, width: 16, height: 16)
    node = RGame::Engine::Node2D.new(x:, y:)
    node.add_component(components::BoxCollider.new(width:, height:, layer: :wall))
    scene.add_node(node)
  end

  def body(node) = node.get_component(components::CharacterBody)
  def grab(node) = node.get_component(described_class)
  def collider(node) = node.get_component(components::BoxCollider)

  def walk(node, x, y) = body(node).set_intent(x, y)
  def hold_grab = backend.hold(controls::KEY_LSHIFT)
  def let_go = backend.release(controls::KEY_LSHIFT)

  describe 'a crate held' do
    it 'comes along backwards, a pull' do
      hero = hero_at(100.0, 100.0)
      crate = crate_at(116.0, 100.0)
      hold_grab
      tick
      walk(hero, -1, 0)
      tick(10)
      expect([hero.x, crate.x]).to eq([90.0, 106.0])
    end

    it 'goes ahead forwards, a push with no pushes: declared' do
      hero = hero_at(100.0, 100.0)
      crate = crate_at(116.0, 100.0)
      hold_grab
      tick
      walk(hero, 1, 0)
      tick(10)
      expect([hero.x, crate.x]).to eq([110.0, 126.0])
    end

    it 'comes along sideways' do
      hero = hero_at(100.0, 100.0)
      crate = crate_at(116.0, 100.0)
      hold_grab
      tick
      walk(hero, 0, -1)
      tick(10)
      expect([hero.y, crate.y]).to eq([90.0, 90.0])
    end

    it 'is the node #holding answers' do
      hero_at(100.0, 100.0)
      crate = crate_at(116.0, 100.0)
      hold_grab
      tick(2)
      expect(grab(scene.children.first).holding).to be(crate)
    end

    it 'is let go the tick the action is released' do
      hero = hero_at(100.0, 100.0)
      crate = crate_at(116.0, 100.0)
      hold_grab
      tick
      walk(hero, -1, 0)
      tick(10)
      let_go
      tick(10)
      expect([hero.x, crate.x, grab(hero).holding]).to eq([80.0, 106.0, nil])
    end
  end

  describe 'a crate that cannot move' do
    it 'stops the mover pushing it into a wall, reporting the crate' do
      hero = hero_at(256.0, 100.0)
      crate = crate_at(272.0, 100.0)
      reports = []
      body(hero).on_blocked { |by, axis| reports << [by, axis] }
      hold_grab
      tick
      walk(hero, 1, 0)
      tick(10)
      expect([hero.x, crate.x, reports]).to eq([256.0, 272.0, [[collider(crate), :x]]])
    end

    it 'stops the mover dragging it sideways into a wall' do
      hero = hero_at(100.0, 100.0)
      crate = crate_at(116.0, 100.0)
      wall_at(116.0, 68.0)
      hold_grab
      tick
      walk(hero, 0, -1)
      tick(40)
      expect([hero.y, crate.y]).to eq([84.0, 84.0])
    end

    it 'stays in hand when the mover backs into a wall, and neither moves' do
      wall_at(84.0, 100.0)
      hero = hero_at(100.0, 100.0)
      crate = crate_at(116.0, 100.0)
      hold_grab
      tick
      walk(hero, -1, 0)
      tick(10)
      expect([hero.x, crate.x]).to eq([100.0, 116.0])
    end
  end

  describe 'what it does not hold' do
    it 'holds nothing out of range, and the mover walks as ever' do
      hero = hero_at(100.0, 100.0)
      crate = crate_at(160.0, 100.0)
      hold_grab
      tick
      walk(hero, -1, 0)
      tick(10)
      expect([hero.x, crate.x, grab(hero).holding]).to eq([90.0, 160.0, nil])
    end

    it 'holds nothing without the action' do
      hero = hero_at(100.0, 100.0)
      crate = crate_at(116.0, 100.0)
      tick
      walk(hero, -1, 0)
      tick(10)
      expect([hero.x, crate.x]).to eq([90.0, 116.0])
    end

    it 'does not hold a node on its layer with no Pushable' do
      hero = hero_at(100.0, 100.0)
      crate = crate_at(116.0, 100.0, pushable: false)
      hold_grab
      tick
      walk(hero, -1, 0)
      tick(10)
      expect([hero.x, crate.x]).to eq([90.0, 116.0])
    end

    it 'lets go of a crate that is freed' do
      hero = hero_at(100.0, 100.0)
      crate = crate_at(116.0, 100.0)
      hold_grab
      tick
      crate.queue_free
      tick
      expect(grab(hero).holding).to be_nil
    end
  end

  it 'lets each player hold their own crate' do
    left = hero_at(100.0, 100.0, player: one)
    right = hero_at(100.0, 150.0, player: two)
    near_left = crate_at(116.0, 100.0)
    near_right = crate_at(116.0, 150.0)
    hold_grab
    backend.hold(controls::PAD_Y, device: controls.gamepad(0))
    tick
    walk(left, -1, 0)
    walk(right, 0, 1)
    tick(10)
    expect([near_left.x, near_right.y, grab(left).holding, grab(right).holding])
      .to eq([106.0, 160.0, near_left, near_right])
  end

  it 'needs a Mover on its node' do
    node = RGame::Engine::Node2D.new
    node.add_component(described_class.new(layer: :crate, range: 32))
    expect { scene.add_node(node) }.to raise_error(/needs a RGame::Engine::Components::Mover/)
  end

  # Warmed past the row boundary at y 128, which the pair crosses on the eighth
  # step. Straddling it, they fill more cells at once than before, and the
  # spatial hash takes one Array for each cell in use at once.
  it 'allocates nothing on a step that drags a crate' do
    hero = hero_at(100.0, 100.0)
    crate_at(116.0, 100.0)
    hold_grab
    tick
    walk(hero, 0, 1)
    tick(5)
    expect { tick }.to allocate_nothing.after_warmup(10).over(20)
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
