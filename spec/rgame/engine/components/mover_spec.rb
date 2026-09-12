# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::Mover do
  # Unit scope: the base class on its own, and the scenes no single mover's spec builds —
  # different movers in one world. What each mover promises about being stopped is
  # spec/support/shared_examples/a_mover.rb, run from each mover's own spec.
  let(:scene) { RGame::Engine::Node2D.new.tap { it.scene = it } }

  before { scene.add_component(RGame::Engine::Components::CollisionWorld.new(cell_size: 64)) }

  def tick(count = 1) = count.times { scene.update(1.0 / 60) }

  def box(node, layer:)
    node.add_component(RGame::Engine::Components::BoxCollider.new(width: 16, height: 16, layer: layer))
  end

  it 'moves nothing on its own, since take_step is an empty hook' do
    node = RGame::Engine::Node2D.new(x: 5.0, y: 6.0)
    node.add_component(described_class.new)
    scene.add_node(node)
    scene.enter_tree
    tick(10)
    expect([node.x, node.y]).to eq([5.0, 6.0])
  end

  # The scene two components that answer the same question have to be able to share: a
  # character and a thrown crate, each declaring the other. Built from both sides at once,
  # because each passing its own spec is exactly what does not prove this.
  # rubocop:disable RSpec/MultipleMemoizedHelpers -- the scene is two movers, and each side is
  # a node, a collider and a component: naming all six is what lets the assertions read.
  describe 'a CharacterBody and a blocked Velocity in one scene' do
    let(:hero_node) { RGame::Engine::Node2D.new(x: 100.0, y: 100.0) }
    let(:crate_node) { RGame::Engine::Node2D.new(x: 160.0, y: 100.0) }
    let(:hero_collider) { box(hero_node, layer: :hero) }
    let(:crate_collider) { box(crate_node, layer: :crate) }
    let(:body) { RGame::Engine::Components::CharacterBody.new(speed: 60.0, blocked_by: [:crate]) }
    let(:crate) { RGame::Engine::Components::Velocity.new(vx: -60.0, blocked_by: [:hero]) }

    before do
      hero_collider
      crate_collider
      hero_node.add_component(body)
      crate_node.add_component(crate)
      scene.add_node(hero_node)
      scene.add_node(crate_node)
      scene.enter_tree
      body.set_intent(1.0, 0.0)
    end

    # 44 px of gap closing at 2 px a step: they meet after 22 steps and neither passes.
    it 'stops each against the other' do
      tick(60)
      expect(crate_node.x - hero_node.x).to eq(16.0)
    end

    it 'reports each to the other, once' do
      hero_stopped_by = []
      crate_stopped_by = []
      body.on_blocked { hero_stopped_by << it }
      crate.on_blocked { crate_stopped_by << it }
      tick(60)
      expect([hero_stopped_by, crate_stopped_by]).to eq([[crate_collider], [hero_collider]])
    end
  end
  # rubocop:enable RSpec/MultipleMemoizedHelpers

  # ThrustController is not a mover: it writes a Velocity, so a ship is stopped by what its
  # Velocity declares, with nothing on the controller.
  it 'stops a ThrustController ship by what its Velocity declares' do
    wall = RGame::Engine::Node2D.new(x: 200.0, y: 0.0)
    wall.add_component(RGame::Engine::Components::BoxCollider.new(width: 16, height: 400, layer: :wall))
    ship = RGame::Engine::Node2D.new(x: 150.0, y: 100.0)
    box(ship, layer: :ship)
    ship.add_component(RGame::Engine::Components::Velocity.new(blocked_by: [:wall]))
    controller = RGame::Engine::Components::ThrustController.new(turn_speed: 1.0, accel: 600.0, max_speed: 300.0)
    ship.add_component(controller)
    scene.add_node(wall)
    scene.add_node(ship)
    scene.enter_tree

    controller.control(RGame::Engine::Actions.new(axes: { turn: 0.0, thrust: 1.0 }))
    tick(120)
    expect(ship.x).to eq(184.0)
  end
end
