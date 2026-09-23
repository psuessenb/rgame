# frozen_string_literal: true

RSpec.describe RGame::Engine::Debug do
  subject(:debug) { described_class.new }

  let(:renderer) { FakeRenderer.new }
  let(:view) { screen_view }

  # Mounted the way RGame::Game mounts it, since a channel is drawn from the
  # root's component phase.
  let(:root) { RGame::Engine::Node2D.new.tap { it.add_component(debug) } }

  def draw_frame = root.draw(renderer, view)

  describe 'channels' do
    it 'ships the two the engine draws' do
      expect(debug.channels).to eq(%i[stats shapes])
    end

    it 'starts every channel off' do
      expect(debug.channels.map { debug.shows?(it) }).to eq([false, false])
    end

    it 'shows one' do
      debug.show(:shapes)
      expect(debug.shows?(:shapes)).to be(true)
    end

    it 'hides one again' do
      debug.show(:shapes)
      debug.hide(:shapes)
      expect(debug.shows?(:shapes)).to be(false)
    end

    it 'toggles one' do
      debug.toggle(:stats)
      expect(debug.shows?(:stats)).to be(true)
      debug.toggle(:stats)
      expect(debug.shows?(:stats)).to be(false)
    end

    it 'leaves the other channels alone' do
      debug.show(:shapes)
      expect(debug.shows?(:stats)).to be(false)
    end

    # A misspelt channel that never draws looks exactly like one that is off.
    it 'raises for a channel nobody declared' do
      expect { debug.shows?(:shaeps) }
        .to raise_error(KeyError, /no debug channel :shaeps.*the channels are :stats, :shapes/m)
    end

    it 'raises when switching one on' do
      expect { debug.show(:routes) }.to raise_error(KeyError, /no debug channel :routes/)
    end
  end

  describe '#define' do
    it 'adds a channel of the game\'s own' do
      debug.define(:routes) { nil }
      expect(debug.channels).to eq(%i[stats shapes routes])
    end

    it 'starts it off, like every other' do
      debug.define(:routes) { nil }
      expect(debug.shows?(:routes)).to be(false)
    end

    it 'calls its block once per frame while it is on' do
      calls = 0
      debug.define(:routes) { calls += 1 }
      debug.show(:routes)

      2.times { draw_frame }

      expect(calls).to eq(2)
    end

    it 'calls it not at all while it is off' do
      calls = 0
      debug.define(:routes) { calls += 1 }

      draw_frame

      expect(calls).to eq(0)
    end

    it 'hands the block the renderer and the view' do
      seen = nil
      debug.define(:routes) { |r, v| seen = [r, v] }
      debug.show(:routes)

      draw_frame

      expect(seen).to eq([renderer, view])
    end

    # `:debug` is the last band, so a layer at or above its first slot is in it
    # whatever slot the block was handed.
    it 'draws the block in the debug band' do
      debug.define(:routes) { |r, _v| r.rect(0, 0, 4, 4) }
      debug.show(:routes)

      draw_frame

      expect(renderer.calls_to(:rect).map(&:layer))
        .to all(be >= RGame::Util::Z.base(:debug, 0))
    end

    it 'replaces the block of a channel defined again, keeping it on' do
      first = 0
      second = 0
      debug.define(:routes) { first += 1 }
      debug.show(:routes)
      debug.define(:routes) { second += 1 }

      draw_frame

      expect([first, second]).to eq([0, 1])
    end

    it 'refuses a channel the engine draws' do
      expect { debug.define(:shapes) { nil } }
        .to raise_error(ArgumentError, /:shapes is drawn by the engine/)
    end

    it 'refuses a channel with no block' do
      expect { debug.define(:routes) }.to raise_error(ArgumentError, /given none/)
    end

    it 'draws two channels in the order they were defined' do
      drawn = []
      debug.define(:routes) { drawn << :routes }
      debug.define(:costs) { drawn << :costs }
      debug.show(:costs)
      debug.show(:routes)

      draw_frame

      expect(drawn).to eq(%i[routes costs])
    end
  end

  describe 'the :stats channel' do
    it 'draws the overlay while it is on' do
      debug.show(:stats)
      draw_frame
      expect(renderer.drawn?(:text)).to be(true)
    end

    it 'draws nothing while it is off' do
      draw_frame
      expect(renderer.drawn?(:text)).to be(false)
    end

    # A Float, because that is what App#fps hands Game and Game hands here.
    it 'reports the frame rate it was handed' do
      debug.fps = 41.6
      debug.show(:stats)
      draw_frame

      drawn = renderer.calls_to(:text).map { it.args.first }
      expect(drawn[0...drawn.index('FPS')].reverse.join).to eq('42')
    end
  end
end
