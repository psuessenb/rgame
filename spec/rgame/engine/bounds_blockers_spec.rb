# frozen_string_literal: true

RSpec.describe RGame::Engine::BoundsBlockers do
  # A 200x100 world, and a 10x10 box moving inside it. The source needs nothing but two
  # numbers, so a doubled Components::World is the whole of its world.
  subject(:blockers) { described_class.new(bounds: bounds) }

  let(:bounds) { instance_double(RGame::Engine::Components::World, world_width: 200, world_height: 100) }

  def resolve_x(dx, x: 50.0) = blockers.resolve_x(x, 0.0, 10.0, 10.0, dx)
  def resolve_y(dy, y: 50.0) = blockers.resolve_y(0.0, y, 10.0, 10.0, dy)

  it 'lets a step that stays inside alone' do
    expect(resolve_x(20.0)).to eq(70.0)
  end

  it 'stops a step at the left edge' do
    expect(resolve_x(-100.0)).to eq(0.0)
  end

  it 'stops a step at the right edge, a box width short of it' do
    expect(resolve_x(1000.0)).to eq(190.0)
  end

  it 'stops a step at the top edge' do
    expect(resolve_y(-100.0)).to eq(0.0)
  end

  it 'stops a step at the bottom edge' do
    expect(resolve_y(1000.0)).to eq(90.0)
  end

  it 'asks nothing of a zero step' do
    expect([resolve_x(0.0), resolve_y(0.0)]).to eq([50.0, 50.0])
  end

  # A box wider than the world is pinned to the origin rather than clamped into a
  # negative span.
  it 'pins a box wider than the world to the origin' do
    expect(blockers.resolve_x(0.0, 0.0, 500.0, 10.0, 100.0)).to eq(0.0)
  end

  # A source reports an edge and CollisionSystem takes it only when it *restricts* the
  # step, which is what a box already outside the world depends on: this reports the
  # edge, and the system keeps the inward step because the edge is further away than it
  # would have gone. So a box spawned outside is not dragged back in, and walking inward
  # is free.
  describe 'a box that is already outside' do
    it 'is reported at the edge by the source' do
      expect(resolve_x(20.0, x: -100.0)).to eq(0.0)
    end

    it 'is left where a step inward puts it, once the system has chosen' do
      system = RGame::Engine::CollisionSystem.new(blockers: blockers)
      expect(system.resolve_x(-100.0, 0.0, 10.0, 10.0, 20.0)).to eq(-80.0)
    end
  end

  describe '#blocker' do
    it 'is the sentinel, whose layer is :bounds' do
      resolve_x(-100.0)
      expect([blockers.blocker.layer, blockers.blocker.node]).to eq([:bounds, nil])
    end

    it 'is the same object for every body, since the world holds no per-step state' do
      resolve_x(-100.0)
      expect(blockers.blocker).to be(described_class::BOUNDS)
    end

    it 'is nil when the step stayed inside' do
      resolve_x(-100.0)
      resolve_x(1.0)
      expect(blockers.blocker).to be_nil
    end
  end

  # WorldBounds is documented immutable, so the two numbers are read once at construction
  # rather than per step.
  it 'reads the bounds once' do
    blockers
    5.times { resolve_x(1.0) }
    expect(bounds).to have_received(:world_width).once
  end

  it 'allocates nothing per resolve' do
    blockers.resolve_x(50.0, 0.0, 10.0, 10.0, 1000.0)
    expect do
      blockers.resolve_x(50.0, 0.0, 10.0, 10.0, 1000.0)
      blockers.resolve_y(0.0, 50.0, 10.0, 10.0, 1000.0)
    end.to allocate_nothing
  end
end
