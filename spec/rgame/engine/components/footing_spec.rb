# frozen_string_literal: true

# A walker on a map with gaps: it walks east at a pixel a tick, hops when told,
# and falls where its footing says. The scene is the whole composition a game
# builds, a CharacterBody, a Hop and a Footing on one node, in both add orders.
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

  def hero(order: %i[body hop footing], x: 40.0, **)
    node = engine::Node2D.new(x: x, y: 27.0)
    node.add_component(parts::FeetCollider.new(width: 12, height: 6))
    built = { body: parts::CharacterBody.new(speed: 60),
              hop: parts::Hop.new(peak: 10, duration: 0.5, action: nil),
              footing: described_class.new(**) }
    order.each { node.add_component(built[it]) }
    world.add_node(node)
    root.enter_tree
    node
  end

  def body(node) = node.get_component(parts::CharacterBody)
  def hop(node) = node.get_component(parts::Hop)
  def footing(node) = node.get_component(described_class)

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

    it 'refuses a fall that is not positive' do
      expect { described_class.new(fall: 0) }.to raise_error(ArgumentError, /fall/)
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

  describe 'on the floor' do
    it 'never falls, however long it stands' do
      node = hero
      ticks(600)

      expect([footing(node).falling?, footing(node).coyote_left, node.scale]).to eq([false, 0.1, 1])
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
      expect(footing(node)).not_to be_falling

      tick
      expect(footing(node)).to be_falling
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

        expect([footing(node).falling?, node.world_x]).to eq([false, 103.0 + late])
      end
    end

    it 'falls when the hop comes seven ticks after the step off' do
      node = hero
      walk_off(node)
      ticks(6)
      hop(node).jump

      expect(footing(node)).to be_falling
    end

    it 'falls on the first tick off the floor with no coyote time' do
      node = hero(coyote: 0)
      walk_off(node)

      expect(footing(node)).to be_falling
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
        states << [footing(node).standing?, footing(node).falling?, footing(node).coyote_left]
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
      expect([hop(node).airborne?, footing(node).falling?]).to eq([true, false])

      ticks(2)
      expect([hop(node).airborne?, footing(node).falling?]).to eq([false, true])
    end
  end

  describe 'the fall' do
    it 'stops the node where it fell and says so once' do
      node = hero(coyote: 0)
      fell = 0
      footing(node).on_fell { fell += 1 }
      walk_off(node)
      ticks(10)

      expect([node.suspended?, node.world_x, fell]).to eq([true, 64.0, 1])
    end

    # The fall began on the step off, so 29 of its 30 ticks have run at the end.
    it 'shrinks the node from 1 toward 0 over the fall' do
      node = hero(coyote: 0, fall: 0.5)
      walk_off(node)
      scales = Array.new(28) { tick.then { node.scale } }

      expect(scales.first).to be > 0.99
      expect(scales.each_cons(2).all? { |a, b| b < a }).to be(true)
      expect(scales.last).to be < 0.1
    end

    it 'frees a node with no Respawn at the end, unscaled and resumed' do
      node = hero(coyote: 0, fall: 0.5)
      walk_off(node)
      ticks(30)

      expect([world.children, node.scale, node.suspended?, footing(node).falling?]).to eq([[], 1, false, false])
    end

    it 'holds mid-shrink while the world around it is paused' do
      node = hero(coyote: 0, fall: 0.5)
      walk_off(node)
      ticks(10)
      world.paused = true
      scale = node.scale
      ticks(60)

      expect([node.scale, footing(node).falling?]).to eq([scale, true])
    end

    it 'ends at once, unscaled and resumed, when the node is taken from its parent' do
      node = hero(coyote: 0, fall: 0.5)
      walk_off(node)
      ticks(10)
      world.remove_node(node)

      expect([node.scale, node.suspended?, footing(node).falling?]).to eq([1, false, false])
    end

    it 'leaves the parent with no trace of the fall once it has ended' do
      node = hero(coyote: 0, fall: 0.5)
      walk_off(node)
      ticks(10)
      root.add_node(node)
      tick

      expect(world.children).to eq([])
    end
  end

  # Walking from 40, the centre steps off at 64 on tick 24. In the default order
  # the footing reads it the same tick, and in the others at most one later.
  describe 'add order' do
    %i[body hop footing].permutation.each do |order|
      it "falls on tick 30 or 31, added as #{order.join(', ')}" do
        node = hero(order: order)
        body(node).set_intent(1, 0)
        fell_on = (1..40).find { tick.then { footing(node).falling? } }

        expect(fell_on).to be_between(30, 31)
      end

      it "crosses with a hop six ticks after the step off, added as #{order.join(', ')}" do
        node = hero(order: order)
        walk_off(node)
        ticks(5)
        hop(node).jump
        ticks(40)

        expect(footing(node)).not_to be_falling
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
      world.add_node(node)
      root.enter_tree
      walk_off(node)
      hop(node).jump
      ticks(40)

      expect([footing(node).falling?, node.world_x]).to eq([false, 104.0])
    end
  end
end
