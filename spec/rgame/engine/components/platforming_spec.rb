# frozen_string_literal: true

# Top-down platforming, composed: every part a game adds for it, on one map at once. Each
# part has its own spec; this one is the scene that uses all of them, which none of those
# builds.
#
# A chasm runs from x 128 to 352, the whole height of the map, with ground on either side.
# A 64x48 platform shuttles across it, its centre from x 170 to 310 and back at 30 px/s,
# never touching a bank. Two heroes and a wandering NPC stand on it, and a crate stands on
# the far bank. A dock, a 64x48 platform that does not move, lies flush against the near
# bank lower down.
RSpec.describe 'Top-down platforming' do # rubocop:disable RSpec/DescribeClass -- a composition of six classes, not one
  let(:root) do
    engine::Node2D.new.tap do |scene|
      scene.scene = scene
      map = WalledTileMap.build(Array.new(12) { "#{'.' * 8}#{'~' * 14}#{'.' * 8}" })
      scene.add_component(parts::TileWorld.new(map: map, tilemap_id: :map))
      scene.add_component(parts::CollisionWorld.new(cell_size: 64))
    end
  end
  let(:world) { root.get_component(parts::TileWorld) }

  def engine = RGame::Engine
  def parts = RGame::Engine::Components
  def dt = 1.0 / 60

  def node_of(components, order, x:, y:)
    node = engine::Node2D.new(x: x, y: y)
    (order == :reversed ? components.reverse : components).each { node.add_component(it) }
    root.add_node(node)
  end

  def slab(x, y, order, route: nil)
    components = [parts::BoxCollider.new(width: 64, height: 48, offset_x: -32, offset_y: -24, layer: :platform),
                  parts::Platform.new]
    components << parts::PathFollow.new(path: route, speed: 30, loop: true) if route
    node_of(components, order, x:, y:).get_component(parts::Platform)
  end

  # A hero stands on the shuttle over the chasm, so its respawn point is on the near
  # bank, set before it attaches.
  def hero(x, y, order)
    node_of([parts::FeetCollider.new(width: 12, height: 6, layer: :hero),
             parts::CharacterBody.new(speed: 60, blocked_by: %i[tiles npc]),
             parts::Hop.new(peak: 10, duration: 0.5, action: nil),
             parts::Footing.new(coyote: 0.1),
             parts::Respawn.new(flash: 0.5).set_point(60.0, 96.0)], order, x:, y:)
  end

  def npc(x, y, order)
    node_of([parts::FeetCollider.new(width: 12, height: 6, layer: :npc),
             parts::CharacterBody.new(speed: 30, blocked_by: %i[tiles gaps hero]),
             parts::WanderController.new(rng: Random.new(5), change_interval: 0.5..1.5, idle_chance: 0.1),
             parts::Footing.new], order, x:, y:)
  end

  def crate(x, y, order)
    node_of([parts::BoxCollider.new(width: 16, height: 16, offset_x: -8, offset_y: -16, layer: :crate),
             parts::Pushable.new(blocked_by: %i[tiles hero crate]),
             parts::Footing.new(coyote: 0),
             parts::Respawn.new(flash: 0.5)], order, x:, y:)
  end

  def footing(node) = node.get_component(parts::Footing)
  def body(node) = node.get_component(parts::CharacterBody)

  def tick
    root.update(dt)
    root.sweep_freed
  end

  def ticks(count) = count.times { tick }

  # rubocop:disable RSpec/MultipleMemoizedHelpers -- the scene is six things, and each example
  # reads most of them; two are the file's own map and world.
  %i[forward reversed].each do |order|
    describe "with each node's components added #{order}" do
      let(:shuttle) { slab(170.0, 96.0, order, route: engine::Path.new([[170.0, 96.0], [310.0, 96.0]])) }
      let(:heroes) { [hero(150.0, 100.0, order), hero(165.0, 100.0, order)] }
      let(:wanderer) { npc(190.0, 115.0, order) }
      let(:box) { crate(370.0, 40.0, order) }

      before do
        shuttle
        heroes
        wanderer
        box
        root.enter_tree
      end

      it 'carries both heroes and the NPC across the chasm and back, and drops none of them' do
        tick # everybody boards
        offsets = heroes.map { it.x - shuttle.node.x }
        standing = []
        600.times do
          tick
          standing << [*heroes, wanderer].all? { footing(it).platform.equal?(shuttle) }
        end
        expect([standing.uniq, heroes.map { it.x - shuttle.node.x }, [*heroes, wanderer].map { footing(it).falling? }])
          .to match([[true], offsets.map { be_within(1e-6).of(it) }, [false, false, false]])
      end

      it 'keeps the NPC on the platform, stopped at its edges' do
        stops = 0
        body(wanderer).on_blocked { |by| stops += 1 if by.layer == :gaps }
        900.times do
          tick
          raise 'the NPC left the platform' unless footing(wanderer).platform.equal?(shuttle)
        end
        expect(stops).to be > 0
      end

      # Walking north 30 px during a hop leaves the platform's top edge behind, and the
      # hero lands on the gap beyond it, falls for 0.4 s and comes back on the near bank.
      it 'lets one hero hop off into the chasm and come back, while the other rides on' do
        leaper, stayer = heroes
        ticks(60)
        leaper.get_component(parts::Hop).jump
        body(leaper).set_intent(0, -1)
        ticks(30)
        body(leaper).set_intent(0, 0)
        ticks(3) # the hop lands on its 31st tick, on the gap
        fell = footing(leaper).falling?
        ticks(60)
        expect([fell, leaper.x, leaper.y, footing(leaper).platform.nil?, footing(stayer).platform.equal?(shuttle),
                shuttle.riders.size]).to eq([true, 60.0, 96.0, true, true, 2])
      end

      it 'drops a crate pushed into the chasm, and brings it back' do
        box.get_component(parts::Pushable).push(-24.0, 0.0)
        tick
        fell = footing(box).falling?
        ticks(60)
        expect([fell, box.x, box.y, footing(box).falling?]).to eq([true, 370.0, 40.0, false])
      end
    end
  end
  # rubocop:enable RSpec/MultipleMemoizedHelpers

  # The dock's box runs from x 128 to 192 and y 136 to 184, flush with the near bank.
  describe 'a mover kept on the floor, on a platform that meets the ground' do
    let(:dock) { slab(160.0, 160.0, :forward) }
    let(:walker) { npc(180.0, 163.0, :forward) }

    before do
      dock
      walker.remove_component(parts::WanderController)
      root.enter_tree
    end

    it 'steps off the platform onto the ground' do
      body(walker).set_intent(-1, 0)
      ticks(180)
      expect([walker.x, footing(walker).platform.nil?, footing(walker).falling?]).to match([be < 128.0, true, false])
    end

    it 'stops at the platform’s far edge, over the chasm' do
      body(walker).set_intent(1, 0)
      ticks(180)
      expect([walker.x, footing(walker).platform.equal?(dock)]).to match([be_within(1e-6).of(192.0), true])
    end
  end

  # One definition of the floor: along a line across ground, gap and platform, standing,
  # boarding and the :gaps blocker give the same answer at every point. A probe with a
  # 2x2 box stands at each point in turn, with coyote time long enough never to fall.
  describe 'the floor' do
    let(:probe) do
      engine::Node2D.new.tap do |node|
        node.add_component(parts::BoxCollider.new(width: 2, height: 2, offset_x: -1, offset_y: -1))
        node.add_component(parts::Footing.new(coyote: 1000))
        root.add_node(node)
      end
    end

    # A step the blocker lets through lands on exactly `x - 1.0 + step`, and one it stops
    # at least FLOOR_EDGE short of it.
    def blocked?(x, y, step)
      (world.gap_blockers.resolve_x(x - 1.0, y - 1.0, 2, 2, step) - (x - 1.0 + step)).abs > 1e-12
    end

    def answers_at(x, y)
      probe.x = x
      probe.y = y
      footing(probe)._update(dt)
      floor = world.floor_at?(x, y)
      col = world.col_at(x)
      row = world.row_at(y)
      [footing(probe).standing? == floor,
       footing(probe).platform.nil? == (!floor || !world.gap?(col, row)),
       blocked?(x, y, 0.25) == (floor && !world.floor_at?(x + 0.25, y)),
       blocked?(x, y, -0.25) == (floor && !world.floor_at?(x - 0.25, y))]
    end

    it 'agrees with itself across the bank, the dock, the chasm and the shuttle' do
      slab(160.0, 160.0, :forward)
      slab(250.0, 96.0, :forward)
      root.enter_tree
      points = (80..400).step(0.25).flat_map { |x| [[x.to_f, 160.0], [x.to_f, 96.0]] }
      disagreements = points.reject { |x, y| answers_at(x, y).all? }
      expect(disagreements).to eq([])
    end
  end
end
