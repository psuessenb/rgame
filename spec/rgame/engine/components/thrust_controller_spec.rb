# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::ThrustController do
  subject(:controller) do
    described_class.new(turn_speed: 4.0, accel: 100.0, max_speed: 200.0)
  end

  let(:node)     { RGame::Engine::Node2D.new }
  let(:velocity) { RGame::Engine::Components::Velocity.new }

  before do
    node.add_component(velocity)
    node.add_component(controller)
    node.enter_tree # on_attach pulls the Velocity sibling
  end

  # Both actions this controller reads, with the example's values over them.
  def actions(**axes)
    RGame::Engine::Actions.new(axes: { turn: 0.0, thrust: 0.0 }.merge(axes))
  end

  describe '#control' do
    it 'maps the turn axis to angular velocity' do
      controller.control(actions(turn: 1.0))
      expect(velocity.spin).to eq(4.0)
    end
  end

  describe '#update' do
    it 'accelerates along the heading — angle 0 faces +x, so it moves right' do
      controller.control(actions(thrust: 1.0)) # node.angle stays 0 = +x
      controller.update(0.1)
      expect(velocity.vx).to be > 0
      expect(velocity.vy).to be_within(1e-9).of(0.0)
    end

    it 'does not accelerate without thrust input' do
      controller.control(actions(thrust: 0.0))
      controller.update(0.1)
      expect([velocity.vx, velocity.vy]).to eq([0.0, 0.0])
    end

    it 'clamps the resulting speed to max_speed' do
      controller.control(actions(thrust: 1.0))
      100.times { controller.update(0.1) } # far more than enough to exceed max_speed
      expect(Math.hypot(velocity.vx, velocity.vy)).to be_within(1e-9).of(200.0)
    end
  end
end
