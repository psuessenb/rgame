# frozen_string_literal: true

RSpec.describe Engine::DebugOverlay do
  subject(:overlay) { described_class.new }

  let(:renderer) { instance_double(FakeRenderer, text: nil, text_width: 10, text_height: 16) }

  # The overlay always draws through #text with a z and colour; a row is just a string.
  def drew(string)
    have_received(:text).with(string, anything, anything, z: anything, color: anything)
  end

  describe 'visibility' do
    it 'starts hidden' do
      expect(overlay).not_to be_visible
    end

    it 'toggles on and off' do
      overlay.toggle
      expect(overlay).to be_visible
      overlay.toggle
      expect(overlay).not_to be_visible
    end
  end

  describe '#draw' do
    context 'when hidden' do
      it 'draws nothing' do
        overlay.draw(renderer, 640, 480, 60)
        expect(renderer).not_to have_received(:text)
      end
    end

    context 'when visible' do
      before do
        overlay.toggle
        overlay.draw(renderer, 640, 480, 60)
      end

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

      it 'places the overlay inside the bottom-right corner' do
        expect(renderer).to have_received(:text)
          .with('FPS', satisfy { |x| x < 640 }, satisfy { |y| y.between?(240, 480) }, z: anything, color: anything)
      end
    end

    it 'draws a single 0 digit for a zero value' do
      overlay.toggle
      overlay.draw(renderer, 640, 480, 0)
      expect(renderer).to drew('0').at_least(:once)
    end
  end
end
