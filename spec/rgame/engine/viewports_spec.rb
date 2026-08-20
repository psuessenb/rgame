# frozen_string_literal: true

RSpec.describe RGame::Engine::Viewports do
  def player(id, active: true)
    RGame::Engine::Player.new(
      id: id, device: active ? RGame::Util::Controls.gamepad(id) : nil
    )
  end

  let(:players)   { RGame::Engine::Players.new([player(0), player(1)]) }
  let(:viewports) { described_class.new(players, width: 640, height: 480) }

  def rects = viewports.views.map { |v| [v.x, v.y, v.width, v.height] }

  describe 'as a root-scoped system' do
    it 'is reachable from a node deep in the tree' do
      root = RGame::Engine::Node2D.new
      mounted = root.add_component(described_class.new(players, width: 640, height: 480))
      leaf = root.add_node(RGame::Engine::Node2D.new).add_node(RGame::Engine::Node2D.new)

      expect(leaf.system(described_class)).to equal(mounted)
    end
  end

  describe 'one view per active player' do
    it 'gives two players a row each' do
      expect(rects).to eq([[0, 0, 640, 240], [0, 240, 640, 240]])
    end

    it 'hands each view its own player' do
      expect(viewports.views.map { |v| v.player.id }).to eq([0, 1])
    end

    it 'hands each view that player\'s camera' do
      expect(viewports.views.map(&:camera))
        .to eq([players[0].camera, players[1].camera])
    end

    # An empty seat gets no share of the screen, so the other player gets it all
    # rather than half of it with a black band.
    it 'skips a player with no device' do
      waiting = RGame::Engine::Players.new([player(0), player(1, active: false)])
      expect(described_class.new(waiting, width: 640, height: 480).views.size).to eq(1)
    end

    it 'gives the one active player the whole window' do
      waiting = RGame::Engine::Players.new([player(0), player(1, active: false)])
      view = described_class.new(waiting, width: 640, height: 480).views.first
      expect([view.width, view.height]).to eq([640, 480])
    end
  end

  describe 'the screen view' do
    # The screen-space band: the whole window, no camera. What the platform
    # hands the tree, and what a HUD lays itself out against.
    it 'is the whole window' do
      expect([viewports.screen.x, viewports.screen.y,
              viewports.screen.width, viewports.screen.height])
        .to eq([0, 0, 640, 480])
    end

    it 'looks through no camera' do
      expect(viewports.screen.camera).to be_nil
    end
  end

  describe 'cameras' do
    # Each camera is clamped against its *own* rect, which is the whole reason a
    # camera does not carry a size: two players sharing a world see different
    # amounts of it.
    it 'resolves each against the rect it will be drawn into' do
      players.each do |p|
        p.camera.world_width = 5000
        p.camera.world_height = 5000
        p.camera.center_on(1000, 1000)
      end
      viewports.refresh

      expect(players[0].camera.y).to eq(1000 - 120) # half of a 240-tall row
    end
  end

  describe 'resizing' do
    it 'recomputes the rects' do
      viewports.resize(800, 600)
      expect(rects).to eq([[0, 0, 800, 300], [0, 300, 800, 300]])
    end

    it 'recomputes the screen view too' do
      viewports.resize(800, 600)
      expect([viewports.screen.width, viewports.screen.height]).to eq([800, 600])
    end
  end

  describe 'solo' do
    let(:cinematic) { RGame::Engine::Camera.new }

    it 'refuses to collapse without a camera to look through' do
      expect { viewports.solo!(nil) }.to raise_error(ArgumentError, /needs a camera/)
    end

    # Deferred, like queue_free: this is reachable from anywhere including a
    # draw, and a draw now runs once per view.
    it 'does not take effect until the tick applies it' do
      viewports.solo!(cinematic)
      expect(viewports.views.size).to eq(2)
    end

    it 'collapses to one screen-wide view once applied' do
      viewports.solo!(cinematic)
      viewports.update(0.016)
      expect(rects).to eq([[0, 0, 640, 480]])
    end

    it 'looks through the camera it was given, not a player\'s' do
      viewports.solo!(cinematic)
      viewports.update(0.016)
      expect(viewports.views.first.camera).to equal(cinematic)
    end

    it 'reports itself as solo' do
      viewports.solo!(cinematic)
      viewports.update(0.016)
      expect(viewports).to be_solo
    end

    it 'goes back to a view per player on split!' do
      viewports.solo!(cinematic)
      viewports.update(0.016)
      viewports.split!
      viewports.update(0.016)
      expect(rects.size).to eq(2)
    end

    # Player cameras are untouched while solo, so splitting back resumes rather
    # than restarts.
    it 'leaves the players\' own cameras alone' do
      players[0].camera.center_on(300, 300)
      viewports.solo!(cinematic)
      viewports.update(0.016)
      expect(players[0].camera.target_x).to eq(300)
    end
  end

  # refresh runs once per frame, and Views and rects are both reused rather than
  # rebuilt — a handful of objects a frame is exactly the steady drip the debug
  # overlay's Δ/f exists to catch.
  it 'refreshes without allocating' do
    viewports.refresh
    expect { viewports.refresh }.to allocate_nothing
  end

  it 'hands back the same View objects frame to frame' do
    first = viewports.views.first
    viewports.refresh
    expect(viewports.views.first).to equal(first)
  end
end
