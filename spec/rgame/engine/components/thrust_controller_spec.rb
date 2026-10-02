# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::ThrustController do
  subject(:controller) do
    described_class.new(turn_speed: 4.0, accel: 100.0)
  end

  let(:node)     { RGame::Engine::Node2D.new }
  let(:velocity) { RGame::Engine::Components::Velocity.new }

  before do
    node.add_component(velocity)
    node.add_component(controller)
    node.enter_tree # _attach pulls the Velocity sibling
  end

  # Both actions this controller reads, with the example's values over them.
  def actions(**axes)
    RGame::Engine::Actions.new(axes: { turn: 0.0, thrust: 0.0 }.merge(axes))
  end

  describe '#_control' do
    it 'maps the turn axis to angular velocity' do
      controller._control(actions(turn: 1.0))
      expect(velocity.spin).to eq(4.0)
    end

    it 'accelerates along the heading — angle 0 faces +x' do
      controller._control(actions(thrust: 1.0))
      expect([velocity.ax, velocity.ay]).to eq([100.0, 0.0])
    end

    it 'accelerates down a node turned a quarter clockwise' do
      node.angle = Math::PI / 2
      controller._control(actions(thrust: 1.0))
      expect([velocity.ax.round(9), velocity.ay]).to eq([0.0, 100.0])
    end

    it 'stops accelerating once the thrust is let go' do
      controller._control(actions(thrust: 1.0))
      controller._control(actions(thrust: 0.0))
      expect([velocity.ax, velocity.ay]).to eq([0.0, 0.0])
    end

    it 'leaves the velocity itself to the Velocity' do
      controller._control(actions(turn: 1.0, thrust: 1.0))
      expect([velocity.vx, velocity.vy]).to eq([0.0, 0.0])
    end
  end

  # A ship whose controller is gone drifts on at the velocity it had.
  describe '#_detach' do
    it 'gives the Velocity back the spin and acceleration it had at attach' do
      gravity = RGame::Engine::Components::Velocity.new(ay: 50.0, spin: 0.5)
      ship = RGame::Engine::Node2D.new
      ship.add_component(gravity)
      ship.add_component(described_class.new(turn_speed: 4.0, accel: 100.0))
      ship.enter_tree
      ship.control(actions(turn: 1.0, thrust: 1.0))
      ship.remove_component(described_class)

      expect([gravity.spin, gravity.ax, gravity.ay]).to eq([0.5, 0.0, 50.0])
    end
  end

  # A game ticks the whole tree's control before any update, so these drive the node
  # as a game does. A ship flies the same whichever of its two components came first.
  describe 'add order' do
    def ship(order, drag: 0.0)
      parts = {
        velocity: RGame::Engine::Components::Velocity.new(drag:, max_speed: 200.0),
        controller: described_class.new(turn_speed: 4.0, accel: 600.0)
      }
      RGame::Engine::Node2D.new.tap do |node|
        order.each { node.add_component(parts.fetch(it)) }
        node.enter_tree
      end
    end

    def fly(node, ticks, **axes)
      ticks.times do
        node.control(actions(**axes))
        node.update(1.0 / 60)
      end
    end

    [%i[velocity controller], %i[controller velocity]].each do |order|
      it "moves on the tick thrust starts, added as #{order.join(', ')}" do
        node = ship(order)
        fly(node, 1, thrust: 1.0)

        expect(node.x).to be_within(1e-9).of(600.0 / 3600)
      end
    end

    it 'flies a turning, dragged ship at its top speed to the same place in both' do
      first, second = [%i[velocity controller], %i[controller velocity]].map { ship(it, drag: 0.5) }
      [first, second].each { fly(it, 90, turn: 1.0, thrust: 1.0) }

      expect([second.x, second.y, second.angle]).to eq([first.x, first.y, first.angle])
    end

    # A thousand ticks at 4 rad/s turn the ship ten times, so its heading crosses every
    # quadrant, and from the twentieth tick on it is clamped to its top speed. A coasting
    # ship facing left would accelerate by cos θ × 0, which is -0.0 and allocates.
    it 'flies and coasts without allocating per tick' do
      node = ship(%i[velocity controller], drag: 0.5)
      thrusting = actions(turn: 1.0, thrust: 1.0)
      coasting = actions(turn: 1.0)
      dt = 1.0 / 60

      expect do
        node.control(thrusting)
        node.update(dt)
      end.to allocate_nothing.after_warmup(30)
      expect do
        node.control(coasting)
        node.update(dt)
      end.to allocate_nothing
    end
  end
end
