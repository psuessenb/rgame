# frozen_string_literal: true

RSpec.describe Engine::Components::PathFollow do
  subject(:follow) { described_class.new(path: path, speed: 50.0) }

  # An L-shaped road: right 100, then down 100 (two segments, total length 200).
  let(:path) { Engine::Path.new([[0.0, 0.0], [100.0, 0.0], [100.0, 100.0]]) }
  let(:node) { Engine::Node2D.new(x: 999.0, y: 999.0) }

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
end
