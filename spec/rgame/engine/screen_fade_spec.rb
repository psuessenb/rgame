# frozen_string_literal: true

RSpec.describe RGame::Engine::ScreenFade do
  def color = RGame::Util::Color
  def glare = color.new(255, 255, 255, 160)

  let(:renderer) { FakeRenderer.new }
  let(:fade) { described_class.new(color: color::BLACK) }

  def step(seconds, dt: 0.1)
    (seconds / dt).round.times { fade.update(dt) }
  end

  def draw(view = screen_view) = fade.draw(renderer, view)

  def rects = renderer.calls_to(:rect)

  def finishes
    count = 0
    fade.on_finished { count += 1 }
    -> { count }
  end

  describe 'a fade just built' do
    it 'is clear, still, and not covered' do
      expect([fade.opacity, fade.running?, fade.covered?]).to eq([0, false, false])
    end

    it 'draws nothing' do
      draw

      expect(renderer.calls).to be_empty
    end

    it 'sits in the overlay band unless given another' do
      expect([fade.band, described_class.new(band: :hud).band]).to eq(%i[overlay hud])
    end

    it 'refuses a colour that is not a Color, as a flash does' do
      expect { described_class.new(color: [0, 0, 0]) }.to raise_error(TypeError, /must be a/)
      expect { fade.flash(0.2, color: 0xFFFFFFFF) }.to raise_error(TypeError, /must be a/)
    end
  end

  describe '#cover' do
    it 'fades to opaque over its duration, and is then covered' do
      fade.cover(0.4)
      step(0.2)
      halfway = fade.opacity
      step(0.2)

      expect(halfway).to be_within(1e-9).of(0.5)
      expect([fade.opacity, fade.running?, fade.covered?]).to eq([1.0, false, true])
    end

    it 'draws its colour over the view, faded by its own opacity' do
      fade.cover(0.4)
      step(0.1)
      draw

      expect(rects.map { [it.args, it.options[:color]] }).to eq([[[0, 0, 640, 480], color::BLACK]])
      expect(rects.first.transforms.map(&:name)).to include(:faded)
    end

    it 'starts from where a reveal got to, and turns back from there' do
      fade.cover(0.4)
      step(0.4)
      fade.reveal(0.4)
      step(0.1)
      fade.cover(0.4)
      step(0.1)

      expect(fade.opacity).to be_within(1e-9).of(0.75 + (0.25 * 0.25))
    end
  end

  describe '#reveal' do
    it 'reveals from covered when it starts with its opacity set to 1' do
      fade.opacity = 1
      covered = fade.covered?
      fade.reveal(0.4)
      step(0.2)

      expect(covered).to be(true)
      expect(fade.opacity).to be_within(1e-9).of(0.5)
    end

    it 'fades back to clear, and a clear fade draws nothing again' do
      fade.cover(0.2)
      step(0.2)
      fade.reveal(0.2)
      step(0.2)
      draw

      expect([fade.opacity, fade.covered?]).to eq([0.0, false])
      expect(renderer.calls).to be_empty
    end
  end

  describe '#flash' do
    before { fade.flash(0.4, color: glare) }

    it 'rises to its colour at half its duration' do
      step(0.2)
      draw

      expect(fade.opacity).to be_within(1e-9).of(1.0)
      expect(rects.last.options[:color]).to eq(glare)
    end

    it 'falls back to clear at its end' do
      step(0.4)

      expect([fade.opacity, fade.running?]).to eq([0.0, false])
    end

    it 'then draws in the fade\'s own colour again' do
      step(0.4)
      fade.cover(0.4)
      step(0.1)
      draw

      expect(rects.last.options[:color]).to eq(color::BLACK)
    end

    it 'flashes in the fade\'s own colour unless given one' do
      fade.flash(0.4)
      step(0.1)
      draw

      expect(rects.last.options[:color]).to eq(color::BLACK)
    end
  end

  describe '#color=' do
    it 'changes the colour a cover draws in, one under way included' do
      fade.cover(0.4)
      step(0.1)
      fade.color = glare
      draw

      expect([fade.color, rects.last.options[:color]]).to eq([glare, glare])
    end

    it 'leaves a flash under way in its own colour until it ends' do
      fade.flash(0.4, color: color::WHITE)
      step(0.1)
      fade.color = glare
      draw
      step(0.3)
      fade.cover(0.4)
      step(0.1)
      draw

      expect(rects.map { it.options[:color] }).to eq([color::WHITE, glare])
    end

    it 'refuses a colour that is not a Color' do
      expect { fade.color = :black }.to raise_error(TypeError, /must be a/)
    end
  end

  describe 'on_finished' do
    it 'fires once when a cover, a reveal or a flash ends' do
      count = finishes
      fade.cover(0.2)
      step(1.0)
      fade.reveal(0.2)
      step(1.0)
      fade.flash(0.2)
      step(1.0)

      expect(count.call).to eq(3)
    end

    it 'does not fire for one replaced before its end' do
      count = finishes
      fade.cover(0.4)
      step(0.2)
      fade.reveal(0.4)
      step(0.4)

      expect(count.call).to eq(1)
    end
  end

  it 'holds still while paused, since time reaches it only through update' do
    fade.cover(0.4)
    step(0.2)
    fade.paused = true
    step(0.2)

    expect(fade.opacity).to be_within(1e-9).of(0.5)
  end

  describe 'each frame' do
    before do
      fade.flash(1_000.0)
      fade.update(1.0)
    end

    it 'allocates nothing to step' do
      expect { fade.update(0.016) }.to allocate_nothing
    end

    it 'allocates nothing to draw' do
      quiet = QuietRenderer.new
      view = screen_view

      expect { fade.draw(quiet, view) }.to allocate_nothing
    end
  end

  describe 'the view it fills' do
    def covered_fade
      described_class.new.tap do |node|
        node.cover(0.1)
        node.update(0.1)
      end
    end

    def player(id) = RGame::Engine::Player.new(id:, device: RGame::Util::Controls.gamepad(id))

    let(:players) { RGame::Engine::Players.new([player(0), player(1)]) }
    let(:viewports) { RGame::Engine::Viewports.new(players, width: 640, height: 480) }
    let(:root) do
      RGame::Engine::Node2D.new.tap do |node|
        node.add_component(players)
        node.add_component(viewports)
      end
    end

    def draw_frame
      viewports.refresh
      root.draw(renderer, viewports.screen)
    end

    it 'covers the whole window at the root' do
      root.add_node(covered_fade)
      draw_frame

      expect(rects.map(&:args)).to eq([[0, 0, 640, 480]])
    end

    it 'covers one player\'s region under their PlayerLayer' do
      root.add_node(RGame::Engine::PlayerLayer.new(player: players[1])).add_node(covered_fade)
      draw_frame

      expect(rects.map(&:args)).to eq([[0, 0, 640, 240]])
      expect(renderer.calls_to(:clipped).map(&:args)).to eq([[0, 240, 640, 240]])
    end

    it 'covers each camera\'s view under a WorldView, where each view is drawn' do
      players[0].camera.center_on(1000, 1000)
      players[1].camera.center_on(200, 300)
      root.add_node(RGame::Engine::WorldView.new).add_node(covered_fade)
      draw_frame

      expect(rects.map(&:args)).to eq(viewports.views.map { [it.origin_x, it.origin_y, 640, 240] })
      expect(rects.map(&:args).uniq.size).to eq(2)
    end
  end
end
