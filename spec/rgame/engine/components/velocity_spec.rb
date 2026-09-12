# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::Velocity do
  subject(:velocity) { described_class.new(vx: 5.0, vy: -3.0, spin: 2.0) }

  let(:node) { RGame::Engine::Node2D.new(x: 10.0, y: 20.0, angle: 1.0) }

  before { node.add_component(velocity) }

  describe '#update' do
    it 'advances position and angle by velocity times the timestep' do
      velocity.update(2.0)
      expect([node.x, node.y, node.angle]).to eq([20.0, 14.0, 5.0])
    end
  end

  it 'defaults to no motion' do
    still = described_class.new
    RGame::Engine::Node2D.new(x: 7.0).tap { it.add_component(still) }
    expect { still.update(1.0) }.not_to(change { still.node.x })
  end

  it_behaves_like 'a mover' do
    def build_mover(blocked_by:, heading: [1, 0])
      described_class.new(vx: 60.0 * heading[0], vy: 60.0 * heading[1], blocked_by: blocked_by)
    end
  end

  # Standing in for every Mover: the edge is resolved by Mover's adapter, which all three
  # share, and a Velocity is the one of them that needs no intent or path to get there.
  it_behaves_like 'a world edge response' do
    let(:stopped_by) { [] }

    def add_response(node, vx:)
      node.add_component(RGame::Engine::Components::BoxCollider.new(width: 10, height: 10))
      node.add_component(described_class.new(vx: vx, blocked_by: [:bounds]))
          .on_blocked { |by| stopped_by << by.layer }
    end

    def responded?(_node, _from) = stopped_by.include?(:bounds)
  end

  # Being stopped is a position question. A box does not turn with its node, so the angle
  # has nothing to be blocked by, and the velocity is the intent a handler may act on.
  describe 'when blocked' do
    let(:scene) { RGame::Engine::Node2D.new.tap { it.scene = it } }
    let(:wall) { RGame::Engine::Node2D.new(x: 30.0, y: 0.0) }
    let(:pressed) { described_class.new(vx: 60.0, vy: 0.0, spin: 2.0, blocked_by: [:wall]) }
    let(:mover) { RGame::Engine::Node2D.new(x: 13.0, y: 0.0) }

    before do
      scene.add_component(RGame::Engine::Components::CollisionWorld.new(cell_size: 64))
      wall.add_component(RGame::Engine::Components::BoxCollider.new(width: 4, height: 64, layer: :wall))
      mover.add_component(RGame::Engine::Components::BoxCollider.new(width: 16, height: 16))
      mover.add_component(pressed)
      scene.add_node(wall)
      scene.add_node(mover)
      scene.enter_tree
      2.times { scene.update(0.5) }
    end

    it 'still turns the node' do
      expect(mover.angle).to eq(2.0)
    end

    it 'keeps its velocity' do
      expect([pressed.vx, mover.x]).to eq([60.0, 14.0])
    end
  end
end
