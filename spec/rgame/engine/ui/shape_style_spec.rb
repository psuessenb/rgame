# frozen_string_literal: true

RSpec.describe RGame::Engine::UI::ShapeStyle do
  let(:renderer) { FakeRenderer.new }
  let(:states) { %i[idle focused pressed disabled] }

  def drawn(style, state, width = 120, height = 40)
    renderer.clear
    style.draw(renderer, state, width, height)
    renderer.calls
  end

  describe 'building one' do
    it 'refuses a shape it cannot draw' do
      expect { described_class.new(shape: :hexagon) }.to raise_error(ArgumentError, /hexagon/)
    end

    # The late failure the ui.json spec guards against for nine-slices: a style
    # that only breaks the first frame a button is disabled.
    it 'refuses colours with a state missing, naming it' do
      colors = described_class::COLORS.except(:disabled)
      expect { described_class.new(colors: colors) }.to raise_error(KeyError, /disabled/)
    end

    it 'keeps the colours it was given' do
      style = described_class.new(colors: described_class::COLORS.merge(idle: RGame::Util::Color.new(1, 2, 3)),
                                  outline: RGame::Util::Color.new(4, 5, 6))
      expect([style.colors[:idle], style.outline]).to eq([RGame::Util::Color.new(1, 2, 3),
                                                          RGame::Util::Color.new(4, 5, 6)])
    end

    it 'refuses content colours with a state missing, naming it' do
      content = described_class::CONTENT.except(:focused)
      expect { described_class.new(content: content) }.to raise_error(KeyError, /focused/)
    end

    it 'has a shared default' do
      expect(described_class::DEFAULT.shape).to eq(:rect)
    end
  end

  describe 'z' do
    # Every shipped button draws its label and icon at z: 1, so a style stays
    # at 0 or below and names its z, rather than leaning on the default.
    %i[rect disc].each do |shape|
      it "draws a #{shape} at z 0 or below, naming it, in every state" do
        style = described_class.new(shape: shape)
        zs = states.flat_map { |state| drawn(style, state).map { |call| call.options[:z] } }
        expect(zs).to all(be <= 0)
      end
    end

    it 'draws the outline under the fill' do
      calls = drawn(described_class.new, :focused)
      expect(calls.map { |call| call.options[:z] }).to eq([-1, 0])
    end
  end

  describe 'the rectangle' do
    let(:style) { described_class.new }

    # The same inset in every state, so a button does not change size as its
    # state does: focus only uncovers the ring the fill leaves.
    it 'insets the fill by the border in every state' do
      fills = states.map { |state| drawn(style, state).find { |call| call.options[:z].zero? }.args }
      expect(fills).to all(eq([3, 3, 114, 34]))
    end

    it 'fills with the colour for the state' do
      colors = states.map { |state| drawn(style, state).last.options[:color] }
      expect(colors).to eq(described_class::COLORS.values_at(*states))
    end

    describe 'the outline' do
      it 'covers the whole slot while focused or pressed' do
        outlines = %i[focused pressed].map { |state| drawn(style, state).first }
        expect(outlines.map { |call| [call.args, call.options[:color]] })
          .to all(eq([[0, 0, 120, 40], described_class::OUTLINE]))
      end

      it 'is not drawn while idle or disabled' do
        counts = %i[idle disabled].map { |state| drawn(style, state).size }
        expect(counts).to eq([1, 1])
      end
    end
  end

  describe 'the disc' do
    let(:style) { described_class.new(shape: :disc) }

    it 'is centred in the slot, inset by the border' do
      fills = states.map { |state| drawn(style, state, 64, 80).last.args }
      expect(fills).to all(eq([32.0, 40.0, 29.0]))
    end

    it 'fits the shorter side with its outline' do
      outline = drawn(style, :focused, 80, 64).first
      expect([outline.name, outline.args]).to eq([:circle, [40.0, 32.0, 32.0]])
    end
  end

  # Not `color: nil`, which the renderer reads as white.
  describe 'leaving a part out' do
    it 'draws no fill in a state whose colour is nil' do
      style = described_class.new(colors: described_class::COLORS.merge(idle: nil))
      expect(drawn(style, :idle)).to be_empty
    end

    it 'draws no outline when outline is nil' do
      style = described_class.new(outline: nil)
      expect(drawn(style, :focused).size).to eq(1)
    end

    it 'draws no disc fill for a nil colour either' do
      style = described_class.new(shape: :disc, colors: described_class::COLORS.merge(focused: nil))
      expect(drawn(style, :focused).map { |call| call.options[:z] }).to eq([-1])
    end
  end

  describe 'allocation' do
    let(:renderer) { QuietRenderer.new }

    %i[rect disc].each do |shape|
      it "draws a #{shape} in every state without allocating" do
        color = ->(r, g, b) { RGame::Util::Color.new(r, g, b) }
        style = described_class.new(shape: shape,
                                    colors: { idle: color[1, 2, 3], focused: color[4, 5, 6],
                                              pressed: color[7, 8, 9], disabled: color[1, 1, 1] })
        expect { states.each { |state| style.draw(renderer, state, 64, 48) } }.to allocate_nothing
      end
    end
  end

  describe 'the content colour' do
    # The pressed fill is gold, and so is IconButton's pressed tint: without a
    # dark content colour a pressed icon vanishes into its own disc.
    it 'is dark while pressed, where the fill is gold' do
      expect(described_class.new.content_color(:pressed)).to eq(RGame::Util::Color.new(46, 34, 24))
    end

    it "leaves the button's own colour in every other state" do
      expect(%i[idle focused disabled].map { described_class.new.content_color(it) }).to all(be_nil)
    end

    it 'takes what it is given' do
      style = described_class.new(content: described_class::CONTENT.merge(idle: RGame::Util::Color.new(1, 2, 3)))
      expect(style.content_color(:idle)).to eq(RGame::Util::Color.new(1, 2, 3))
    end
  end
end
