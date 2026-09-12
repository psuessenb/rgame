# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::PathFollow do
  subject(:follow) { described_class.new(path: path, speed: 50.0) }

  # An L-shaped road: right 100, then down 100 (two segments, total length 200).
  let(:path) { RGame::Engine::Path.new([[0.0, 0.0], [100.0, 0.0], [100.0, 100.0]]) }
  let(:node) { RGame::Engine::Node2D.new(x: 999.0, y: 999.0) }

  # add_component fires on_attach immediately only once the node is in the tree.
  before do
    node.add_component(follow)
    node.enter_tree
  end

  it 'parks the node on the first waypoint when it enters the tree' do
    expect([node.x, node.y]).to eq([0.0, 0.0])
  end

  it 'advances along the first segment by speed * dt' do
    follow.update(1.0) # 50 px along the +x leg
    expect([node.x, node.y]).to eq([50.0, 0.0])
  end

  it 'turns the corner onto the next segment within a single step' do
    follow.update(2.0) # 100 px: exactly to the corner, no further
    expect([node.x, node.y]).to eq([100.0, 0.0])

    follow.update(1.0) # 50 px down the second leg
    expect([node.x, node.y]).to eq([100.0, 50.0])
  end

  it 'crosses multiple segments in one large step' do
    follow.update(3.0) # 150 px: 100 across the first leg, 50 down the second
    expect([node.x, node.y]).to eq([100.0, 50.0])
  end

  describe 'reaching the end' do
    it 'clamps to the final waypoint instead of overshooting' do
      follow.update(10.0) # 500 px >> 200 px total
      expect([node.x, node.y]).to eq([100.0, 100.0])
    end

    it 'reports finished and emits on_finished exactly once' do
      finishes = 0
      follow.on_finished { finishes += 1 }

      follow.update(10.0)
      expect(follow).to be_finished
      expect(finishes).to eq(1)

      follow.update(10.0) # further updates are inert
      expect(finishes).to eq(1)
    end
  end

  describe 're-entering the tree (pool recycle)' do
    it 'restarts the walk from the first waypoint' do
      follow.update(10.0) # walk all the way to the end
      expect(follow).to be_finished

      node.exit_tree
      node.enter_tree # reacquired from a pool and re-added

      expect(follow).not_to be_finished
      expect([node.x, node.y]).to eq([0.0, 0.0]) # parked back at the first waypoint
    end

    it 'walks and finishes again on its next life, reusing the one listener' do
      finishes = 0
      follow.on_finished { finishes += 1 } # wired once, as a pooled entity would

      follow.update(10.0) # first life reaches the end
      node.exit_tree
      node.enter_tree     # recycled
      follow.update(10.0) # second life reaches the end

      expect(finishes).to eq(2)
    end
  end

  it_behaves_like 'a mover' do
    def build_mover(blocked_by:, heading: [1, 0])
      road = RGame::Engine::Path.new([[170.0, 100.0], [170.0 + (830.0 * heading[0]), 100.0 + (830.0 * heading[1])]])
      described_class.new(path: road, speed: 60.0, blocked_by: blocked_by)
    end
  end

  # rubocop:disable RSpec/MultipleMemoizedHelpers -- two of the six are the file's own road and
  # node, inherited and unused here; this scene names only the four it builds.
  # One pixel a tick, in whole numbers, so arrival ticks are exact. A gate on the road is
  # a collider the follower is blocked by, and it is opened by moving it away.
  describe 'held on the way' do
    let(:scene) { RGame::Engine::Node2D.new.tap { it.scene = it } }
    let(:gate) { RGame::Engine::Node2D.new(x: 50.0, y: 0.0) }
    let(:walker) { RGame::Engine::Node2D.new }
    let(:held) do
      described_class.new(path: RGame::Engine::Path.new([[0.0, 0.0], [100.0, 0.0]]), speed: 1.0, blocked_by: [:gate])
    end

    before do
      scene.add_component(RGame::Engine::Components::CollisionWorld.new(cell_size: 64))
      gate.add_component(RGame::Engine::Components::BoxCollider.new(width: 4, height: 16, layer: :gate))
      walker.add_component(RGame::Engine::Components::BoxCollider.new(width: 16, height: 16))
      walker.add_component(held)
      scene.add_node(gate)
      scene.add_node(walker)
      scene.enter_tree
    end

    def tick = scene.update(1.0)

    # The box's right edge reaches the gate at x = 50 once the node is at 34, on tick 34.
    # Held for thirty ticks more, then let through.
    def hold_then_open
      64.times { tick }
      gate.x = 1000.0
    end

    it 'waits where it was stopped rather than being placed further on' do
      hold_then_open
      tick
      expect(walker.x).to eq(35.0)
    end

    it 'arrives as many ticks late as it was held' do
      ticks = 0
      finished_on = nil
      held.on_finished { finished_on = ticks }
      hold_then_open
      ticks = 64
      until finished_on || ticks > 200
        ticks += 1
        tick
      end
      expect(finished_on).to eq(130) # 100 ticks of walking, plus the 30 it stood at the gate
    end

    it 'does not finish while stopped short of the last waypoint' do
      gate.x = 110.0 # past the end of the road, with the box's far edge running into it
      200.times { tick }
      expect(held).not_to be_finished
    end
  end
  # rubocop:enable RSpec/MultipleMemoizedHelpers
end
