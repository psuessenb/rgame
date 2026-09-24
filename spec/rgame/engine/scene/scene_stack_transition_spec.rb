# frozen_string_literal: true

# A scene that logs what reached it each tick: whether it was controlled or
# updated, and the edges of fire it read.
class SpecTransitionScene < RGame::Engine::Node2D
  attr_reader :log

  def initialize(**)
    super
    @log = []
  end

  def _control(actions)
    @log << :control
    @log << :pressed if actions.pressed?(:fire)
  end

  def _update(_dt) = @log << :update
end

# Each tick runs as RGame::Game runs one: a poll, a control of the whole tree,
# an update and a sweep. A tick is an eighth of a second, so a Fade of half a
# second covers in four ticks and reveals in four more, with no rounding.
# rubocop:disable RSpec/MultipleMemoizedHelpers -- the input, the tree and three scenes every group shares
RSpec.describe RGame::Engine::Scene::SceneStack do
  let(:fade) { RGame::Engine::Scene::Fade.new(cover: 0.5, reveal: 0.5) }
  let(:backend) { FakeInputBackend.new }
  let(:players) { RGame::Engine::Players.new([RGame::Engine::Player.new(id: 0, device: RGame::Util::Controls::KEYBOARD)]) }
  let(:root) { RGame::Engine::Node2D.new.tap { it.add_component(players) } }
  let(:stack) { root.add_component(described_class.new) }
  let(:first) { SpecTransitionScene.new }
  let(:second) { SpecTransitionScene.new }

  def dt = 0.125

  def tick(times = 1)
    times.times do
      players.poll(backend, dt)
      root.control(players)
      root.update(dt)
      root.sweep_freed
    end
  end

  # How opaque the cover is drawn: 0 when it draws nothing, and 1.0 when it
  # draws with no `faded` around it.
  def cover_drawn
    renderer = FakeRenderer.new
    root.draw(renderer, screen_view)
    rect = renderer.calls_to(:rect).find { it.options[:color] == fade.color }
    return 0 unless rect

    rect.transforms.find { it.name == :faded }&.args&.first || 1.0
  end

  # The cover drawn after each of `ticks` ticks, and the scene on top then.
  def run(ticks)
    Array.new(ticks) do
      tick
      [cover_drawn, stack.current]
    end
  end

  before do
    root.enter_tree
    stack.push(first)
    tick
    first.log.clear
    stack.transition = fade
  end

  # Rule 7.
  describe 'a switch with a transition' do
    it 'covers, lands in the sweep after the cover ends, and reveals' do
      stack.replace(second)

      expect(run(9)).to eq([[0.25, first], [0.5, first], [0.75, first], [1.0, second],
                            [0.75, second], [0.5, second], [0.25, second], [0, second], [0, second]])
    end

    it 'is transitioning from the ask until the reveal ends' do
      stack.replace(second)
      states = Array.new(9) do
        tick
        stack.transitioning?
      end

      expect(states).to eq([true] * 7 + [false, false])
    end

    it 'covers the host\'s view in the overlay band, over every scene' do
      stack.replace(second)
      tick
      renderer = FakeRenderer.new
      root.draw(renderer, screen_view)
      cover = renderer.calls_to(:rect).last

      expect(cover.args).to eq([0, 0, 640, 480])
      expect(cover.layer).to be >= RGame::Util::Z.base(:overlay, 0)
    end

    it 'covers in the colour of the transition it runs' do
      white = RGame::Engine::Scene::Fade.new(color: RGame::Util::Color::WHITE, cover: 0.5, reveal: 0.5)
      stack.replace(second, transition: white)
      tick
      renderer = FakeRenderer.new
      root.draw(renderer, screen_view)

      expect(renderer.calls_to(:rect).last.options[:color]).to eq(RGame::Util::Color::WHITE)
    end

    it 'fires on_changed as the switch lands, under the cover' do
      seen = []
      stack.on_changed { seen << cover_drawn }
      stack.replace(second)
      tick(8)

      expect(seen).to eq([1.0])
    end
  end

  # Rule 8.
  describe 'the scenes during a transition' do
    before do
      stack.replace(second)
      tick(9)
    end

    it 'does not control or update the scene leaving' do
      expect(first.log).to be_empty
    end

    it 'updates the scene arriving from the tick after it lands, and controls it once the reveal ends' do
      expect(second.log).to eq(%i[update update update update control update])
    end
  end

  # Rule 9.
  describe 'a press begun during a transition' do
    def press = backend.hold(RGame::Util::Controls::KEY_SPACE)
    def release = backend.release(RGame::Util::Controls::KEY_SPACE)

    before { stack.replace(second) }

    it 'reaches the scene arriving as held, with no edges' do
      tick(5)
      press
      tick(4)
      release
      tick

      expect(second.log).not_to include(:pressed)
    end

    it 'leaves the next press to the scene' do
      tick(9)
      press
      tick

      expect(second.log.last(3)).to eq(%i[control pressed update])
    end
  end

  # Rule 10.
  describe 'a switch asked for during a transition' do
    let(:third) { SpecTransitionScene.new }

    it 'replaces the one waiting, when asked for during the cover' do
      stack.replace(second)
      tick(2)
      stack.replace(third)

      expect(run(2)).to eq([[0.75, first], [1.0, third]])
      expect(second.log).to be_empty
    end

    it 'covers again from where the reveal got to, when asked for during the reveal' do
      stack.replace(second)
      tick(6)
      stack.replace(third)

      expect(run(4)).to eq([[0.625, second], [0.75, second], [0.875, second], [1.0, third]])
    end

    it 'joins the transition under way when it has none of its own' do
      stack.replace(second)
      tick(2)
      stack.replace(third, transition: nil)

      expect(run(3)).to eq([[0.75, first], [1.0, third], [0.75, third]])
    end
  end

  # Rule 11.
  describe 'a push onto an empty stack' do
    it 'starts covered, lands in the first sweep, and reveals' do
      stack.pop
      tick(9)
      stack.push(second)
      covered = cover_drawn

      expect(covered).to eq(1.0)
      expect(run(5)).to eq([[1.0, second], [0.75, second], [0.5, second], [0.25, second], [0, second]])
    end
  end

  describe 'a pop' do
    it 'covers, takes the top scene off, and reveals the one below' do
      stack.push(second, transition: nil)
      tick
      stack.pop

      expect(run(5).map(&:last)).to eq([second, second, second, first, first])
    end
  end

  describe 'a host that is paused' do
    it 'holds the transition where it is' do
      stack.replace(second)
      tick(2)
      root.paused = true
      tick(3)

      expect([cover_drawn, stack.current]).to eq([0.5, first])
    end
  end

  describe 'each tick' do
    it 'allocates nothing while a transition covers and reveals' do
      stack.replace(second)
      tick
      actions = RGame::Engine::Actions.new
      renderer = QuietRenderer.new
      view = screen_view

      expect do
        root.control(actions)
        root.update(dt)
        root.draw(renderer, view)
      end.to allocate_nothing
    end

    it 'allocates nothing once a transition has ended' do
      stack.replace(second)
      tick(10)
      actions = RGame::Engine::Actions.new
      renderer = QuietRenderer.new
      view = screen_view

      expect do
        root.control(actions)
        root.update(dt)
        root.draw(renderer, view)
        root.sweep_freed
      end.to allocate_nothing
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
