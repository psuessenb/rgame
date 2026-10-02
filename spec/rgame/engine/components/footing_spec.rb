# frozen_string_literal: true

# A walker on a map with gaps: it walks east at a pixel a tick, hops when told,
# and falls where its footing says. The scene is the whole composition a game
# builds, a CharacterBody, a Hop, a Footing, a Fall and a Shrink on one node, in
# every add order. Its Fall is how a spec sees the node lose its footing.
RSpec.describe RGame::Engine::Components::Footing do
  # One gap tile wide at x 64..80, and one three wide at 128..176.
  let(:root) do
    engine::Node2D.new.tap do |scene|
      scene.scene = scene
      map = WalledTileMap.build(['............', '....~...~~~.', '............'])
      scene.add_component(parts::TileWorld.new(map: map, tilemap_id: :map))
    end
  end
  let(:world) { root.add_node(engine::Node2D.new) }

  # Its box's centre is 3px above its origin, at (x, 24): the middle of row 1.
  def engine = RGame::Engine
  def parts = RGame::Engine::Components
  def dt = 1.0 / 60

  def hero(order: %i[body hop footing fall shrink], x: 40.0, **)
    node = engine::Node2D.new(x: x, y: 27.0)
    node.add_component(parts::FeetCollider.new(width: 12, height: 6))
    built = { body: parts::CharacterBody.new(speed: 60),
              hop: parts::Hop.new(peak: 10, duration: 0.5, action: nil),
              footing: described_class.new(**),
              fall: parts::Fall.new,
              shrink: parts::Shrink.new }
    order.each { node.add_component(built[it]) }
    world.add_node(node)
    root.enter_tree
    node
  end

  def body(node) = node.get_component(parts::CharacterBody)
  def hop(node) = node.get_component(parts::Hop)
  def footing(node) = node.get_component(described_class)
  def falling?(node) = node.get_component(parts::Fall).falling?

  def tick
    root.update(dt)
    root.sweep_freed
  end

  def ticks(count) = count.times { tick }

  # Walks east until the centre of the box leaves the floor, and answers how many
  # ticks that took. The step off is the last of them.
  def walk_off(node)
    body(node).set_intent(1, 0)
    count = 0
    until !footing(node).standing? || count > 200
      tick
      count += 1
    end
    count
  end

  describe '.new' do
    it 'refuses a negative coyote time' do
      expect { described_class.new(coyote: -0.1) }.to raise_error(ArgumentError, /coyote/)
    end

    it 'takes no fall, naming it' do
      expect { described_class.new(fall: 0.4) }.to raise_error(ArgumentError, /fall/)
    end
  end

  describe 'attaching' do
    it 'raises without a BoxCollider on the node' do
      node = engine::Node2D.new.tap { it.add_component(described_class.new) }
      world.add_node(node)

      expect { root.enter_tree }.to raise_error(RuntimeError, /BoxCollider/)
    end

    it 'raises without a TileWorld on the scene' do
      bare = engine::Node2D.new.tap { it.scene = it }
      node = engine::Node2D.new
      node.add_component(parts::FeetCollider.new(width: 12, height: 6))
      node.add_component(described_class.new)
      bare.add_node(node)

      expect { bare.enter_tree }.to raise_error(RuntimeError, /TileWorld/)
    end
  end

  # `@footing` is what a game names the ivar holding one, and y-sort once kept
  # its own sorting collider in an ivar of that name on every node.
  it 'stays in a node that keeps it in @footing, under a y-sorted parent' do
    keeper = Class.new(engine::Node2D) do
      attr_reader :footing

      def initialize(**)
        super
        add_component(RGame::Engine::Components::FeetCollider.new(width: 12, height: 6))
        @footing = add_component(RGame::Engine::Components::Footing.new)
      end
    end
    sorted = world.add_node(engine::Node2D.new(y_sort: true))
    node = sorted.add_node(keeper.new(x: 40.0, y: 27.0))
    sorted.add_node(keeper.new(x: 40.0, y: 60.0))
    root.enter_tree
    root.draw(FakeRenderer.new, screen_view)

    expect(node.footing).to be_a(described_class)
  end

  describe 'on the floor' do
    it 'never falls, however long it stands' do
      node = hero
      ticks(600)

      expect([falling?(node), footing(node).coyote_left, node.scale]).to eq([false, 0.1, 1])
    end

    it 'stands on a point off the map, which is floor' do
      node = hero(x: -100.0)
      ticks(60)

      expect(footing(node)).to be_standing
    end
  end

  describe 'walking off the floor' do
    it 'falls once it has been off the floor for more than the coyote time' do
      node = hero
      walk_off(node)
      ticks(5)
      expect(falling?(node)).to be(false)

      tick
      expect(falling?(node)).to be(true)
    end

    it 'counts the coyote time down from the step off' do
      node = hero
      walk_off(node)
      ticks(2)

      expect(footing(node).coyote_left).to be_within(1e-9).of(0.1 - (3 * dt))
    end

    # The hop carries it 30px, from 64 + late across the gap's far edge at 80.
    (1..6).each do |late|
      it "crosses a one-tile gap with a hop started #{late} ticks after the step off" do
        node = hero
        walk_off(node)
        ticks(late - 1)
        hop(node).jump
        ticks(40)

        expect([falling?(node), node.world_x]).to eq([false, 103.0 + late])
      end
    end

    it 'falls when the hop comes seven ticks after the step off' do
      node = hero
      walk_off(node)
      ticks(6)
      hop(node).jump

      expect(falling?(node)).to be(true)
    end

    it 'falls on the first tick off the floor with no coyote time, where on_fell sees it' do
      node = hero(coyote: 0)
      fell_at = nil
      node.get_component(parts::Fall).on_fell { fell_at = node.x }
      walk_off(node)

      expect([falling?(node), fell_at, node.x]).to eq([true, 64.0, 64.0])
    end
  end

  describe 'in the air' do
    it 'never falls, and has no coyote time' do
      node = hero(x: 50.0)
      body(node).set_intent(1, 0)
      hop(node).jump
      tick
      states = []
      20.times do
        states << [footing(node).standing?, falling?(node), footing(node).coyote_left]
        tick
      end

      expect(states).to include([false, false, 0.0])
      expect(states.map { it[1] }.uniq).to eq([false])
    end

    it 'falls on the tick it lands on a gap' do
      node = hero(x: 110.0)
      body(node).set_intent(1, 0)
      hop(node).jump
      ticks(30)
      expect([hop(node).airborne?, falling?(node)]).to eq([true, false])

      tick
      expect([hop(node).airborne?, falling?(node)]).to eq([false, true])
    end

    context 'with the node standing at elevation 4' do
      it 'crosses a gap and lands back on its elevation' do
        node = hero(x: 50.0)
        node.elevation = 4
        body(node).set_intent(1, 0)
        hop(node).jump
        ticks(32)

        expect([node.world_x, falling?(node), node.elevation]).to eq([82.0, false, 4])
      end

      it 'falls at its elevation as it lands on a gap' do
        node = hero(x: 110.0)
        node.elevation = 4
        body(node).set_intent(1, 0)
        hop(node).jump
        ticks(32)

        expect([falling?(node), node.elevation]).to eq([true, 4])
      end
    end
  end

  describe 'with no Fall' do
    it 'never suspends the node, which walks on over the gap with no coyote time left' do
      node = hero(order: %i[body hop footing])
      walk_off(node)
      ticks(10)

      expect([node.suspended?, footing(node).standing?, footing(node).coyote_left, node.world_x])
        .to eq([false, false, 0.0, 74.0])
    end

    it 'has no coyote time left once it lands on a gap' do
      node = hero(order: %i[body hop footing], x: 110.0)
      body(node).set_intent(1, 0)
      hop(node).jump
      ticks(32)

      expect([hop(node).airborne?, node.suspended?, footing(node).coyote_left]).to eq([false, false, 0.0])
    end

    it 'starts a Fall added over the gap on the next update' do
      node = hero(order: %i[body hop footing])
      walk_off(node)
      ticks(10)
      fall = node.add_component(parts::Fall.new)
      tick

      expect([fall.falling?, node.suspended?]).to eq([true, true])
    end

    it 'counts its coyote time again once the node stands' do
      node = hero(order: %i[body hop footing])
      walk_off(node)
      ticks(10)
      node.x = 40.0
      tick

      expect(footing(node).coyote_left).to eq(0.1)
    end
  end

  # Walking from 40, the centre steps off at 64 on tick 24. In the default order
  # the footing reads it the same tick, and in the others at most one later. The
  # Fall and the Shrink come before the rest, and after.
  describe 'add order' do
    %i[body hop footing].permutation.flat_map { [%i[fall shrink] + it, it + %i[fall shrink]] }.each do |order|
      it "falls on tick 30 or 31, added as #{order.join(', ')}" do
        node = hero(order: order)
        body(node).set_intent(1, 0)
        fell_on = (1..40).find { tick.then { falling?(node) } }

        expect(fell_on).to be_between(30, 31)
      end

      it "crosses with a hop six ticks after the step off, added as #{order.join(', ')}" do
        node = hero(order: order)
        walk_off(node)
        ticks(5)
        hop(node).jump
        ticks(40)

        expect(falling?(node)).to be(false)
      end
    end

    it 'keeps up a node whose Hop arrives from its _enter_tree, after the Footing' do
      late = Class.new(engine::Node2D) do
        def _enter_tree = add_component(RGame::Engine::Components::Hop.new(peak: 10, duration: 0.5, action: nil))
      end
      node = late.new(x: 40.0, y: 27.0)
      node.add_component(parts::FeetCollider.new(width: 12, height: 6))
      node.add_component(parts::CharacterBody.new(speed: 60))
      node.add_component(described_class.new)
      node.add_component(parts::Fall.new)
      world.add_node(node)
      root.enter_tree
      walk_off(node)
      hop(node).jump
      ticks(40)

      expect([falling?(node), node.world_x]).to eq([false, 104.0])
    end
  end

  # The Footing reads what its Hop and its mover did this tick only when they update
  # before it, as they do in every other group here. Added after it, each is read a
  # tick late, and the mover still takes its step on the tick the fall starts.
  describe 'a sibling added after it' do
    let(:hop_after) { %i[body footing hop fall shrink] }
    let(:mover_after) { %i[hop footing body fall shrink] }

    it 'falls on the tick after it lands on a gap, with the Hop after it' do
      node = hero(order: hop_after, x: 110.0)
      body(node).set_intent(1, 0)
      hop(node).jump
      ticks(31)
      expect([hop(node).airborne?, falling?(node)]).to eq([false, false])

      tick
      expect(falling?(node)).to be(true)
    end

    it 'falls on the second tick off the floor with no coyote time, a step past on_fell, with the mover after it' do
      node = hero(order: mover_after, coyote: 0)
      fell_at = nil
      node.get_component(parts::Fall).on_fell { fell_at = node.x }
      walk_off(node)
      expect(falling?(node)).to be(false)

      tick
      expect([falling?(node), fell_at, node.x]).to eq([true, 64.0, 65.0])
    end

    it 'crosses with a hop seven ticks after the step off, with the mover after it' do
      node = hero(order: mover_after)
      walk_off(node)
      ticks(6)
      hop(node).jump
      ticks(40)

      expect([falling?(node), node.world_x]).to eq([false, 110.0])
    end

    it 'falls when the hop comes eight ticks after the step off, with the mover after it' do
      node = hero(order: mover_after)
      walk_off(node)
      ticks(7)
      hop(node).jump

      expect(falling?(node)).to be(true)
    end
  end

  # From 48 the hop lands on tick 31 at 79, a step inside the narrow gap's far edge
  # at 80. From 49 it lands at 80, on the floor past it. With the Hop on one side
  # of the Footing and the mover on the other, the Footing judges the landing where
  # the node stood a step away.
  describe "a landing a step from a gap's edge" do
    def hop_from(x, order)
      node = hero(order: order, x: x)
      body(node).set_intent(1, 0)
      hop(node).jump
      ticks(35)
      node
    end

    it 'falls landing inside the edge, with the Hop and the mover before it' do
      expect(falling?(hop_from(48.0, %i[body hop footing fall shrink]))).to be(true)
    end

    it 'stands landing inside the edge, with only the Hop after it' do
      expect(falling?(hop_from(48.0, %i[body footing hop fall shrink]))).to be(false)
    end

    it 'stands landing past the edge, with the Hop and the mover before it' do
      expect(falling?(hop_from(49.0, %i[body hop footing fall shrink]))).to be(false)
    end

    it 'falls landing past the edge, with only the mover after it' do
      expect(falling?(hop_from(49.0, %i[hop footing body fall shrink]))).to be(true)
    end
  end
end
