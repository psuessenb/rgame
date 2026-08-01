# frozen_string_literal: true

RSpec.describe RGame::Core::App do
  # Every example builds its own window. That only works because the engine
  # refcounts SDL's lifetime across apps — before it did, a garbage-collected
  # app called SDL_Quit out from under the live ones and the suite segfaulted.
  def app(width: 200, height: 150, caption: 'spec')
    described_class.new(width: width, height: height, caption: caption)
  end

  describe '.new' do
    it 'takes its geometry as keywords and exposes it' do
      subject = app(width: 320, height: 240, caption: 'probe')

      expect(subject.width).to eq(320)
      expect(subject.height).to eq(240)
      expect(subject.caption).to eq('probe')
    end

    it 'renames the window through #caption=' do
      subject = app
      subject.caption = 'renamed'

      expect(subject.caption).to eq('renamed')
    end

    it 'rejects a missing keyword' do
      expect { described_class.new(width: 1, height: 1) }.to raise_error(ArgumentError)
    end

    it 'rejects positional arguments' do
      expect { described_class.new(320, 240, 'x') }.to raise_error(ArgumentError)
    end

    it 'rejects an unknown keyword' do
      expect { app_with_bogus_keyword }.to raise_error(ArgumentError)
    end

    def app_with_bogus_keyword
      described_class.new(width: 1, height: 1, caption: 'x', bogus: 2)
    end
  end

  describe 'the frame lifecycle' do
    # A subclass overrides only the hooks it needs; the rest are inherited
    # no-ops. This one closes itself so the loop terminates.
    let(:probe_class) do
      Class.new(described_class) do
        attr_reader :log

        def initialize
          super(width: 200, height: 150, caption: 'lifecycle')
          @log = Hash.new(0)
        end

        def frame_begin = @log[:frame_begin] += 1
        def draw = @log[:draw] += 1
        def needs_redraw? = (@log[:needs_redraw] += 1).positive?

        def update(dt)
          @log[:update] += 1
          @log[:dt] = dt
          close if @log[:update] >= 5
        end
      end
    end

    it 'drives every hook and stops when the game closes itself' do
      probe = probe_class.new
      probe.run

      expect(probe.log[:update]).to eq(5)
      expect(probe.log[:frame_begin]).to be_positive
      expect(probe.log[:draw]).to be_positive
      expect(probe.log[:needs_redraw]).to be_positive
    end

    it 'always passes the fixed timestep as dt, never wall-clock frame time' do
      probe = probe_class.new
      probe.run

      expect(probe.log[:dt]).to be_within(1e-12).of(1.0 / 60.0)
    end

    it 'returns self from #run' do
      probe = probe_class.new

      expect(probe.run).to be(probe)
    end
  end

  describe '#needs_redraw?' do
    it 'skips the draw while the simulation keeps advancing' do
      probe = Class.new(described_class) do
        attr_reader :draws, :updates

        def initialize
          super(width: 200, height: 150, caption: 'no-draw')
          @draws = 0
          @updates = 0
        end

        def draw = @draws += 1
        def needs_redraw? = false

        def update(_dt)
          @updates += 1
          close if @updates >= 5
        end
      end.new

      probe.run

      expect(probe.updates).to eq(5)
      expect(probe.draws).to be_zero
    end
  end

  describe 'a callback that raises' do
    # The engine runs each callback under rb_protect, stops the loop, and
    # re-raises once the C frame has unwound on its own terms. Without that a
    # raise would longjmp straight through the loop and strand the window.
    def raising_app(hook, error, &)
      Class.new(described_class) do
        define_method(:initialize) { super(width: 200, height: 150, caption: 'boom') }
        define_method(hook) { |*| raise(error, "boom from #{hook}") }
      end.new
    end

    it 'propagates out of #run with its class and message intact' do
      expect { raising_app(:update, KeyError).run }
        .to raise_error(KeyError, 'boom from update')
    end

    it 'keeps the backtrace pointing at the callback that raised' do
      # A real `def`, not define_method: the point of this example is that the
      # backtrace names the game's own method, and define_method would only
      # ever name the block that defined it.
      klass = Class.new(described_class) do
        def initialize = super(width: 200, height: 150, caption: 'boom')
        def update(_dt) = raise(KeyError, 'boom from update')
      end

      begin
        klass.new.run
        raise 'expected the callback to raise'
      rescue KeyError => e
        expect(e.backtrace.join("\n")).to include('update')
      end
    end

    it 'propagates from draw as well' do
      expect { raising_app(:draw, KeyError).run }.to raise_error(KeyError)
    end

    it 'propagates from frame_begin as well' do
      expect { raising_app(:frame_begin, ArgumentError).run }.to raise_error(ArgumentError)
    end

    it 'survives a non-StandardError, which a bare rescue would miss' do
      expect { raising_app(:update, NotImplementedError).run }
        .to raise_error(ScriptError)
    end
  end

  describe 'a non-local exit from a callback' do
    # throw/break/return cannot be replayed after rb_protect pops the tag, and
    # the pending errinfo holds internal throw data that is not safe to touch.
    # Both were segfaults before the engine started reporting this instead.
    it 'is reported as an error rather than crashing the process' do
      thrower = Class.new(described_class) do
        def initialize = super(width: 200, height: 150, caption: 'throw')
        def update(_dt) = throw(:bail, 42)
      end.new

      expect { catch(:bail) { thrower.run } }
        .to raise_error(RuntimeError, /non-local exit/)
    end
  end
end
