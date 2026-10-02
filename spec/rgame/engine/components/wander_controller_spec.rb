# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::WanderController do
  let(:body) { RGame::Engine::Components::CharacterBody.new(speed: 60.0) }
  let(:still) { RGame::Engine::Actions.new }

  # Build an actor node carrying a CharacterBody + a wander controller with the given
  # options, already in the tree (so _attach has run).
  def build(**)
    node = RGame::Engine::Node2D.new
    node.add_component(body)
    controller = node.add_component(described_class.new(**))
    node.enter_tree
    [node, controller]
  end

  describe '#_control' do
    it 'rolls a direction on the first control' do
      _node, controller = build(rng: Random.new(1), idle_chance: 0.0)
      controller._control(still)
      expect([body.move_x, body.move_y]).not_to eq([0.0, 0.0])
    end

    it 'idles when the idle roll wins (idle_chance 1.0)' do
      _node, controller = build(rng: Random.new(1), idle_chance: 1.0)
      controller._control(still)
      expect([body.move_x, body.move_y]).to eq([0.0, 0.0])
    end

    it 'rolls again on the first control after its timer runs out' do
      _node, controller = build(rng: Random.new(1), change_interval: 0.5..0.5)
      controller._control(still)
      controller._update(0.5)
      allow(body).to receive(:set_intent).and_call_original
      controller._control(still)

      expect(body).to have_received(:set_intent).once
    end

    it 'is deterministic for a given seed' do
      _na, ca = build(rng: Random.new(42))
      body_b = RGame::Engine::Components::CharacterBody.new(speed: 60.0)
      nb = RGame::Engine::Node2D.new
      nb.add_component(body_b)
      cb = nb.add_component(described_class.new(rng: Random.new(42)))
      nb.enter_tree

      5.times do
        [ca, cb].each do |controller|
          controller._control(still)
          controller._update(0.5)
        end
      end
      expect([body_b.move_x, body_b.move_y]).to eq([body.move_x, body.move_y])
    end

    it 'does not re-roll a body that nothing can stop before its timer runs out' do
      node, _controller = build(rng: Random.new(7), idle_chance: 0.0, change_interval: 100.0..100.0)
      allow(body).to receive(:set_intent).and_call_original

      30.times do
        node.control(still)
        node.update(0.016)
      end
      expect(body).to have_received(:set_intent).once
    end
  end

  describe '#_update' do
    it 'rolls nothing, even once its timer runs out' do
      _node, controller = build(rng: Random.new(1), change_interval: 0.5..0.5)
      controller._control(still)
      allow(body).to receive(:set_intent).and_call_original
      controller._update(1.0)

      expect(body).not_to have_received(:set_intent)
    end
  end

  describe 'rng:' do
    let(:root) { RGame::Engine::Node2D.new }
    let(:source) { RGame::Engine::Components::RandomSource.new(seed: 9) }

    def wander(**)
      node = root.add_node(RGame::Engine::Node2D.new)
      node.add_component(RGame::Engine::Components::CharacterBody.new(speed: 60.0))
      controller = node.add_component(described_class.new(idle_chance: 0.0, **))
      root.enter_tree
      controller
    end

    it "rolls from the root's RandomSource when given none" do
      root.add_component(source)
      allow(source).to receive(:rand).and_call_original
      wander._control(still)

      expect(source).to have_received(:rand).at_least(:once)
    end

    it 'raises at attach, naming RandomSource, when the root has none' do
      expect { wander }.to raise_error(KeyError, /RandomSource/)
    end

    it "rolls from an rng: passed in, and leaves the root's source alone" do
      root.add_component(source)
      allow(source).to receive(:rand).and_call_original
      wander(rng: Random.new(9))._control(still)

      expect(source).not_to have_received(:rand)
    end
  end

  # A game ticks the whole tree's control before any update, so these drive the scene as
  # a game does. The room is 64 by 48 pixels inside its walls. A walker rolling every 0.2
  # to 0.5 s at 60 px/s for ten seconds rolls 38 times, and 10 of its steps stop at a wall.
  describe 'add order' do
    def walker(order, idle_chance: 0.25)
      parts = {
        body: RGame::Engine::Components::CharacterBody.new(speed: 60.0, blocked_by: [:tiles]),
        controller: described_class.new(rng: Random.new(4), change_interval: 0.2..0.5, idle_chance:)
      }
      node = RGame::Engine::Node2D.new(x: 48.0, y: 40.0)
      node.add_component(RGame::Engine::Components::BoxCollider.new(width: 8, height: 8, offset_x: -4, offset_y: -4))
      order.each { node.add_component(parts.fetch(it)) }
      room.tap do |scene|
        scene.add_node(node)
        scene.enter_tree
      end
      node
    end

    def room
      RGame::Engine::Node2D.new.tap do |scene|
        scene.scene = scene
        map = WalledTileMap.build(%w[###### #....# #....# #....# ######])
        scene.add_component(RGame::Engine::Components::TileWorld.new(map: map, tilemap_id: :map))
      end
    end

    def track(node, ticks)
      Array.new(ticks) do
        node.root.control(still)
        node.root.update(1.0 / 60)
        [node.x, node.y]
      end
    end

    [%i[body controller], %i[controller body]].each do |order|
      it "moves on the tick it rolls its first heading, added as #{order.join(', ')}" do
        node = walker(order, idle_chance: 0.0)

        expect(track(node, 1)).not_to eq([[48.0, 40.0]])
      end
    end

    it 'walks the same track in both' do
      first, second = [%i[body controller], %i[controller body]].map { track(walker(it), 600) }

      expect(second).to eq(first)
    end
  end

  # A walker boxed in by walls on every side, so whichever way it rolls, a step stops.
  describe 'blocked' do
    let(:scene) { RGame::Engine::Node2D.new.tap { it.scene = it } }
    let(:walker) { RGame::Engine::Node2D.new(x: 100.0, y: 100.0) }
    let(:boxed) { RGame::Engine::Components::CharacterBody.new(speed: 60.0, blocked_by: [:wall]) }

    def wall(x, y, width, height)
      RGame::Engine::Node2D.new(x: x, y: y).tap do |node|
        node.add_component(RGame::Engine::Components::BoxCollider.new(width: width, height: height, layer: :wall))
      end
    end

    before do
      scene.add_component(RGame::Engine::Components::CollisionWorld.new(cell_size: 64))
      [wall(84, 84, 48, 16), wall(84, 116, 48, 16), wall(84, 100, 16, 16), wall(116, 100, 16, 16)]
        .each { scene.add_node(it) }
      walker.add_component(RGame::Engine::Components::BoxCollider.new(width: 16, height: 16))
      walker.add_component(boxed)
      scene.add_node(walker)
    end

    it 're-rolls on the control after a wall stops a step, ignoring the timer' do
      walker.add_component(described_class.new(rng: Random.new(7), idle_chance: 0.0,
                                               change_interval: 100.0..100.0))
      scene.enter_tree
      allow(boxed).to receive(:set_intent).and_call_original

      3.times do
        scene.control(still)
        scene.update(0.016)
      end
      expect(boxed).to have_received(:set_intent).exactly(3).times
    end
  end

  # A chasm under a 48x48 platform shuttling east and west, and an NPC on it kept on the
  # floor by :gaps. The platform moves every tick, so the NPC always moves; only its body
  # can say it was stopped at the edge.
  describe 'carried on a platform' do
    let(:scene) do
      RGame::Engine::Node2D.new.tap do |root|
        root.scene = root
        map = WalledTileMap.build(Array.new(12) { '~' * 20 })
        root.add_component(RGame::Engine::Components::TileWorld.new(map: map, tilemap_id: :map))
      end
    end
    let(:raft) do
      RGame::Engine::Node2D.new.tap do |node|
        node.add_component(RGame::Engine::Components::BoxCollider.new(width: 48, height: 48,
                                                                      offset_x: -24, offset_y: -24))
        node.add_component(RGame::Engine::Components::Platform.new)
        route = RGame::Engine::Path.new([[100.0, 100.0], [220.0, 100.0]])
        node.add_component(RGame::Engine::Components::PathFollow.new(path: route, speed: 30, loop: true))
      end
    end
    let(:stopper) { RGame::Engine::Components::CharacterBody.new(speed: 90.0, blocked_by: [:gaps]) }

    it 're-rolls against the edge of the platform, and never walks off it' do
      npc = RGame::Engine::Node2D.new(x: 100.0, y: 100.0)
      npc.add_component(RGame::Engine::Components::FeetCollider.new(width: 12, height: 6))
      npc.add_component(RGame::Engine::Components::Footing.new)
      npc.add_component(stopper)
      npc.add_component(described_class.new(rng: Random.new(3), idle_chance: 0.0, change_interval: 100.0..100.0))
      scene.add_node(raft)
      scene.add_node(npc)
      scene.enter_tree
      allow(stopper).to receive(:set_intent).and_call_original

      600.times do
        scene.control(still)
        scene.update(1.0 / 60)
      end
      footing = npc.get_component(RGame::Engine::Components::Footing)
      expect([npc.suspended?, footing.platform]).to eq([false, raft.get_component(RGame::Engine::Components::Platform)])
      expect(stopper).to have_received(:set_intent).at_least(5).times
    end
  end
end
