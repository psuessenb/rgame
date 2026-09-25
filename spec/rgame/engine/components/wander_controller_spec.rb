# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::WanderController do
  let(:body) { RGame::Engine::Components::CharacterBody.new(speed: 60.0) }

  # Build an actor node carrying a CharacterBody + a wander controller with the given
  # options, already in the tree (so _attach has run).
  def build(**)
    node = RGame::Engine::Node2D.new
    node.add_component(body)
    controller = node.add_component(described_class.new(**))
    node.enter_tree
    [node, controller]
  end

  describe '#update' do
    it 'rolls a direction on the first update' do
      _node, controller = build(rng: Random.new(1), idle_chance: 0.0)
      controller._update(0.016)
      expect([body.move_x, body.move_y]).not_to eq([0.0, 0.0])
    end

    it 'idles when the idle roll wins (idle_chance 1.0)' do
      _node, controller = build(rng: Random.new(1), idle_chance: 1.0)
      controller._update(0.016)
      expect([body.move_x, body.move_y]).to eq([0.0, 0.0])
    end

    it 'is deterministic for a given seed' do
      _na, ca = build(rng: Random.new(42))
      body_b = RGame::Engine::Components::CharacterBody.new(speed: 60.0)
      nb = RGame::Engine::Node2D.new
      nb.add_component(body_b)
      cb = nb.add_component(described_class.new(rng: Random.new(42)))
      nb.enter_tree

      5.times do
        ca._update(0.5)
        cb._update(0.5)
      end
      expect([body_b.move_x, body_b.move_y]).to eq([body.move_x, body.move_y])
    end

    it 'does not re-roll a body that nothing can stop before its timer runs out' do
      _node, controller = build(rng: Random.new(7), idle_chance: 0.0, change_interval: 100.0..100.0)
      allow(body).to receive(:set_intent).and_call_original

      30.times do
        body._update(0.016)
        controller._update(0.016)
      end
      expect(body).to have_received(:set_intent).once
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

    it 're-rolls on the tick a wall stops it, ignoring the timer' do
      walker.add_component(described_class.new(rng: Random.new(7), idle_chance: 0.0,
                                               change_interval: 100.0..100.0))
      scene.enter_tree
      allow(boxed).to receive(:set_intent).and_call_original

      3.times { scene.update(0.016) }
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

      600.times { scene.update(1.0 / 60) }
      footing = npc.get_component(RGame::Engine::Components::Footing)
      expect([footing.falling?, footing.platform]).to eq([false, raft.get_component(RGame::Engine::Components::Platform)])
      expect(stopper).to have_received(:set_intent).at_least(5).times
    end
  end
end
