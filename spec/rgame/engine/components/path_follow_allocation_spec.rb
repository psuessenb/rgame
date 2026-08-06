# frozen_string_literal: true

# Guards PathFollow's per-frame hot path with the `allocate_nothing` matcher: walking an
# enemy along the road runs every frame for every enemy, so it must not leak. Doubles as
# a worked example of the matcher on a real Component#update.
RSpec.describe RGame::Engine::Components::PathFollow do
  # One long segment: the follower walks it for the whole measurement without reaching the
  # end (which would cross the one-off finish + emit). This is the steady-state per-frame
  # case — mid-segment movement, the work every enemy does on the vast majority of frames.
  let(:path) { RGame::Engine::Path.new([[0.0, 0.0], [1_000_000.0, 0.0]]) }
  let(:node) { RGame::Engine::Node2D.new }
  let(:follow) { described_class.new(path: path, speed: 50.0) }

  before do
    node.add_component(follow)
    node.enter_tree # fires on_attach: parks the node on the first waypoint
  end

  it 'walks along the path without allocating per frame' do
    dt = 1.0 / 60.0
    expect { follow.update(dt) }.to allocate_nothing
  end
end
