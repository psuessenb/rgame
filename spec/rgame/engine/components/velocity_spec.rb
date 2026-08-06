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
end
