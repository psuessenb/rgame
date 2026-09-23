# frozen_string_literal: true

RSpec.describe RGame::Engine::DebugOverlay do
  subject(:overlay) { described_class.new }

  let(:renderer) do
    instance_double(FakeRenderer, text: nil, text_width: 10, text_height: 16, layered: nil)
  end

  before { allow(renderer).to receive(:layered).and_yield }

  # The overlay always draws through #text with a colour; a row is just a string.
  def drew(string)
    have_received(:text).with(string, anything, anything, color: anything)
  end

  describe '#draw' do
    describe 'the lines it draws' do
      before { overlay.draw(renderer, screen_view, 60) }

      it 'labels each stat line' do
        expect(renderer).to drew('FPS')
        expect(renderer).to drew('OBJ')
        expect(renderer).to drew('Δ/f')
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

  # Whether the overlay is on is RGame::Engine::Debug's answer, not this
  # class's; #restart is how the channel says it has just gone on, so the first
  # frame reports one frame's allocations rather than every one since anybody
  # last looked.
  describe '#restart' do
    # Δ/f is drawn digit by digit between the OBJ and Δ/f labels, right to left.
    def delta_drawn(recorder)
      drawn = recorder.calls_to(:text).map { it.args.first }
      drawn[(drawn.index('OBJ') + 1)...drawn.index('Δ/f')].reverse.join.to_i
    end

    it 'counts the allocations from then on' do
      Array.new(1000) { Object.new }
      overlay.restart

      recorder = FakeRenderer.new
      overlay.draw(recorder, screen_view, 60)

      expect(delta_drawn(recorder)).to be < 1000
    end
  end
end
