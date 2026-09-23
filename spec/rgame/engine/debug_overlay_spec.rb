# frozen_string_literal: true

RSpec.describe RGame::Engine::DebugOverlay do
  subject(:overlay) { described_class.new }

  let(:renderer) do
    instance_double(FakeRenderer, text: nil, text_width: 10, text_height: 16, layered: nil)
  end
  let(:labels) do
    [described_class::FPS_LABEL, described_class::OBJ_LABEL,
     described_class::RATE_LABEL, described_class::GC_LABEL]
  end

  before { allow(renderer).to receive(:layered).and_yield }

  # The overlay always draws through #text with a colour; a row is just a string.
  def drew(string)
    have_received(:text).with(string, anything, anything, color: anything)
  end

  # What each row reads on screen, by label. A row draws its glyphs right to
  # left and then its label, so the glyphs since the last label, reversed, are
  # its number.
  def rows_drawn
    recorder = FakeRenderer.new
    overlay.draw(recorder, screen_view, 60)
    glyphs = []
    recorder.calls_to(:text).each_with_object({}) do |call, rows|
      text = call.args.first
      next glyphs << text unless labels.include?(text)

      rows[text] = glyphs.reverse.join
      glyphs = []
    end
  end

  def objects_per_second = rows_drawn.fetch(described_class::RATE_LABEL).to_i
  def gc_ms = rows_drawn.fetch(described_class::GC_LABEL)

  def gc_time_of
    before = GC.total_time
    yield
    GC.total_time - before
  end

  # GC ms as the overlay rounds it: to the nearest tenth of a millisecond.
  def as_ms(nanoseconds)
    tenths = (nanoseconds + 50_000) / 100_000
    "#{tenths / 10}.#{tenths % 10}"
  end

  describe '#draw' do
    describe 'the lines it draws' do
      before { overlay.draw(renderer, screen_view, 60) }

      it 'labels each stat line' do
        expect(renderer).to drew('FPS')
        expect(renderer).to drew('OBJ')
        expect(renderer).to drew('OBJ/s')
        expect(renderer).to drew('GC ms')
      end

      it 'draws the number digit by digit (never one interpolated string)' do
        # fps 60 -> the glyphs '6' and '0', drawn separately from cached strings.
        expect(renderer).to drew('6').at_least(:once)
        expect(renderer).to drew('0').at_least(:once)
      end

      it 'draws in the debug band, over every other thing in the frame' do
        expect(renderer).to have_received(:layered).with(:debug)
      end

      it 'places the overlay inside the bottom-right corner' do
        expect(renderer).to have_received(:text)
          .with('FPS', satisfy { |x| x < 640 }, satisfy { |y| y.between?(240, 480) }, color: anything)
      end
    end

    it 'draws a single 0 digit for a zero value' do
      overlay.draw(renderer, screen_view, 0)
      expect(renderer).to drew('0').at_least(:once)
    end

    it 'draws GC ms to a tenth, around a point' do
      expect(gc_ms).to eq('0.0')
    end

    # The rows are taken in #update. A frame drawn twice between two ticks
    # draws the same numbers twice, whatever was allocated in between.
    it 'draws the numbers the last tick took, however often it is drawn' do
      overlay.update(1.0 / 60)
      first = rows_drawn
      Array.new(1000) { Object.new }

      expect(rows_drawn).to eq(first)
    end

    # `App#fps` is a Float, and dividing one by ten never reaches zero: 59.94
    # walks down through 0.6, 0.06 and 0.006, drawing a leading zero at each
    # step until it underflows. Every row is rounded before its digits are
    # taken.
    describe 'a row that arrives as a Float' do
      let(:recorder) { FakeRenderer.new }

      before { overlay.draw(recorder, screen_view, 59.94) }

      def digits_drawn
        drawn = recorder.calls_to(:text).map { it.args.first }
        drawn[0...drawn.index('FPS')]
      end

      it 'rounds it rather than walking it down to nothing' do
        expect(digits_drawn.reverse.join).to eq('60')
      end

      it 'draws one glyph per digit and no more' do
        expect(digits_drawn.length).to eq(2)
      end
    end
  end

  describe '#update' do
    # Through once first, so no count below includes the caches Ruby fills on a
    # method's first call, whichever example happens to run first.
    before do
      overlay.update(1.0)
      overlay.restart
    end

    # A collection landing inside the second allocates a few objects of its
    # own, so these hold it off, as `allocate_nothing` does.
    describe 'OBJ/s' do
      around do |example|
        GC.disable
        example.run
      ensure
        GC.enable
      end

      it 'reads 0 until a whole second of dt has passed' do
        Array.new(1000) { Object.new }
        overlay.update(0.5)

        expect(objects_per_second).to eq(0)
      end

      it 'reports the objects allocated over the last whole second' do
        Array.new(1000) { Object.new } # 1000 objects and the array holding them
        overlay.update(0.5)
        overlay.update(0.5)

        expect(objects_per_second).to be_between(1001, 1010)
      end

      it 'counts per second of dt, so a longer window is scaled to one second' do
        Array.new(1000) { Object.new }
        overlay.update(2.0)

        expect(objects_per_second).to be_between(500, 505)
      end

      it 'starts each second from zero' do
        Array.new(1000) { Object.new }
        overlay.update(1.0)
        overlay.update(1.0)

        expect(objects_per_second).to eq(0)
      end
    end

    describe 'GC ms' do
      it 'reports the longest the collector ran in one tick of the second' do
        overlay.update(0.25)
        spent = gc_time_of { GC.start }
        overlay.update(0.25)
        overlay.update(0.5)

        expect(gc_ms).to eq(as_ms(spent))
      end

      # A hitch is one tick's pause. Two collections in two ticks are two short
      # pauses, not one long one.
      it 'keeps the worst tick rather than adding the ticks up' do
        first = gc_time_of { GC.start }
        overlay.update(0.5)
        second = gc_time_of { GC.start }
        overlay.update(0.5)

        expect(gc_ms).to eq(as_ms([first, second].max))
      end

      it 'reads 0.0 for a second in which the collector never ran' do
        GC.start
        overlay.update(1.0)
        overlay.update(1.0)

        expect(gc_ms).to eq('0.0')
      end
    end
  end

  # Whether the overlay is on is RGame::Engine::Debug's answer, not this
  # class's; #restart is how the channel says it has just gone on, so the first
  # second shown counts from then rather than from whenever anybody last looked.
  describe '#restart' do
    it 'counts the allocations from then on' do
      overlay
      Array.new(1000) { Object.new }
      overlay.restart
      overlay.update(1.0)

      expect(objects_per_second).to be < 1000
    end

    it 'zeroes the rows a second measured before it' do
      Array.new(1000) { Object.new }
      overlay.update(1.0)
      overlay.restart

      expect(rows_drawn.values_at('OBJ/s', 'GC ms')).to eq(['0', '0.0'])
    end
  end
end
