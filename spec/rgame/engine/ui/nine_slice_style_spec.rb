# frozen_string_literal: true

RSpec.describe RGame::Engine::UI::NineSliceStyle do
  let(:style) do
    described_class.new(idle: :button_idle, focused: :button_focus,
                        pressed: :button_pressed, disabled: :button_disabled)
  end

  describe 'building one' do
    it 'names an element per state' do
      expect(style.elements).to eq(idle: :button_idle, focused: :button_focus,
                                   pressed: :button_pressed, disabled: :button_disabled)
    end

    # An atlas missing its disabled element fails where the style is written,
    # not on the first frame a button is disabled.
    it 'refuses to be built with a state missing' do
      expect { described_class.new(idle: :a, focused: :b, pressed: :c) }
        .to raise_error(ArgumentError, /disabled/)
    end

    describe '#with' do
      it 'replaces only the elements it is given' do
        expect(style.with(idle: :mine).elements)
          .to eq(style.elements.merge(idle: :mine))
      end

      it 'leaves the original as it was' do
        style.with(idle: :mine)
        expect(style.elements[:idle]).to eq(:button_idle)
      end

      it 'refuses a state that does not exist' do
        expect { style.with(hovered: :mine) }.to raise_error(ArgumentError, /hovered/)
      end
    end
  end

  describe 'drawing' do
    let(:renderer) { instance_double(FakeRenderer, nine_slice: nil) }

    # Exactly the call PanelButton made before it had a style, keywords and all,
    # which is what keeps the driven reports of every menu that uses one
    # unchanged. The nine-slice default z is 0, under a button's content at 1.
    %i[idle focused pressed disabled].each do |state|
      it "draws the #{state} element over the whole slot" do
        style.draw(renderer, state, 200, 40)
        expect(renderer).to have_received(:nine_slice).with(style.elements.fetch(state), 0, 0, 200, 40)
      end
    end

    it 'refuses a state it has no element for' do
      expect { style.draw(renderer, :hovered, 200, 40) }.to raise_error(KeyError, /hovered/)
    end
  end

  it "names no content colour in any state, leaving the button's own" do
    style = described_class.new(idle: :a, focused: :b, pressed: :c, disabled: :d)
    expect(RGame::Engine::UI::Button::STATES.map { style.content_color(it) }).to all(be_nil)
  end
end
