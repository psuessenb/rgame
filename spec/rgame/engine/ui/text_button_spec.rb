# frozen_string_literal: true

RSpec.describe RGame::Engine::UI::TextButton do
  # Nothing registered: the prototyping promise is that this button draws
  # before any atlas exists, and a FakeRenderer asked for an unregistered
  # nine-slice raises.
  let(:renderer) { FakeRenderer.new }
  let(:root) { RGame::Engine::Node2D.new }

  before { RGame::Engine::I18n.load_hash(en: { play: 'Play' }) }

  def button(label: 'play', **)
    root.add_node(described_class.new(label: label, width: 200, height: 40, **))
        .tap { root.enter_tree }
  end

  def draw
    renderer.clear
    root.draw(renderer, screen_view)
    renderer.calls.reject { |call| call.name == :translated }
  end

  describe 'with no style given' do
    it 'draws with nothing registered with the renderer' do
      button
      expect(draw.map(&:name)).to eq(%i[rect text])
    end

    it 'draws the shared shape style' do
      expect(button.style).to be(RGame::Engine::UI::ShapeStyle::DEFAULT)
    end
  end

  it 'draws only its label with style: nil' do
    button(style: nil)
    expect(draw.map(&:name)).to eq(%i[text])
  end

  describe 'the style' do
    let(:style) { instance_double(RGame::Engine::UI::ShapeStyle, draw: nil) }

    it 'is handed the state and the slot' do
      button(style: style).focused = true
      draw
      expect(style).to have_received(:draw).with(renderer, :focused, 200, 40)
    end

    it 'is handed the disabled state when disabled' do
      button(style: style, enabled: false)
      draw
      expect(style).to have_received(:draw).with(renderer, :disabled, 200, 40)
    end
  end

  describe 'the label' do
    # FakeRenderer's stand-in metrics: 8 pixels a character, 18 a line.
    it 'is centred in the slot' do
      button
      expect(draw.last.args).to eq(['Play', 84.0, 11])
    end

    it 'draws the translation for the current locale' do
      RGame::Engine::I18n.load_hash(de: { play: 'Spielen' })
      button
      english = draw.last.args.first
      RGame::Engine::I18n.locale = :de
      expect([english, draw.last.args.first]).to eq(%w[Play Spielen])
    end

    it 'centres the new translation after a switch' do
      RGame::Engine::I18n.load_hash(de: { play: 'Spielen' })
      button
      draw
      RGame::Engine::I18n.locale = :de
      expect(draw.last.args).to eq(['Spielen', 72.0, 11])
    end

    describe 'with variables' do
      let(:saves) { RGame::Engine::Text.new('continue', :saves) }

      before { RGame::Engine::I18n.load_hash(en: { continue: 'Continue (%{saves})' }) }

      it 'draws the values its last with was given' do
        button(label: saves)
        saves.with(saves: 3)
        expect(draw.last.args.first).to eq('Continue (3)')
      end

      it 'follows a later with, and centres the new text' do
        button(label: saves)
        saves.with(saves: 3)
        draw
        saves.with(saves: 12)
        expect(draw.last.args).to eq(['Continue (12)', 48.0, 11])
      end

      it 'raises on a draw before any with, naming the keyword' do
        button(label: saves)
        expect { draw }.to raise_error(ArgumentError, /needs saves:/)
      end

      it 'draws without allocating while the values are unchanged' do
        item = button(label: saves)
        saves.with(saves: 3)
        quiet = QuietRenderer.new
        item.on_draw(quiet, nil)
        expect { item.on_draw(quiet, nil) }.to allocate_nothing
      end
    end

    it 'draws a literal label in every locale' do
      button(label: RGame::Engine::Text.literal('Ada'))
      RGame::Engine::I18n.load_hash(de: { play: 'Spielen' })
      english = draw.last.args.first
      RGame::Engine::I18n.locale = :de
      expect([english, draw.last.args.first]).to eq(%w[Ada Ada])
    end

    it 'is drawn above everything the style draws, focused or not' do
      item = button
      unfocused = draw
      item.focused = true
      focused = draw
      [unfocused, focused].each do |calls|
        style_z = calls.reject { |call| call.name == :text }.map { |call| call.options[:z] }
        expect(calls.last.options[:z]).to be > style_z.max
      end
    end

    it 'takes its colour from label_color' do
      button(label_color: [1, 2, 3])
      expect(draw.last.options[:color]).to eq(RGame::Util::Color.new(1, 2, 3))
    end

    it 'takes the disabled colour while disabled' do
      button(enabled: false)
      expect(draw.last.options[:color]).to eq(described_class::DISABLED_LABEL_COLOR)
    end

    describe 'on a style that names a content colour' do
      let(:shape_style) { RGame::Engine::UI::ShapeStyle }

      it "takes the style's colour while pressed, so it reads on the gold fill" do
        button.press
        expect(draw.last.options[:color]).to eq(shape_style::CONTENT[:pressed])
      end

      it 'keeps label_color in a state the style leaves nil' do
        button(label_color: [1, 2, 3]).focused = true
        expect(draw.last.options[:color]).to eq(RGame::Util::Color.new(1, 2, 3))
      end

      it 'takes the style colour over the disabled colour when the style names one' do
        style = shape_style.new(content: shape_style::CONTENT.merge(disabled: [7, 8, 9]))
        button(style: style, enabled: false)
        expect(draw.last.options[:color]).to eq(RGame::Util::Color.new(7, 8, 9))
      end
    end

    it 'keeps label_color while pressed on a style that answers only draw' do
      plain = Class.new { def draw(_renderer, _state, _width, _height) = nil }.new
      button(style: plain, label_color: [1, 2, 3]).press
      expect(draw.last.options[:color]).to eq(RGame::Util::Color.new(1, 2, 3))
    end
  end

  it 'draws pressed without allocating' do
    item = button
    item.press
    quiet = QuietRenderer.new
    expect { item.on_draw(quiet, nil) }.to allocate_nothing
  end

  it 'draws without allocating, with array colours given' do
    item = button(label_color: [1, 2, 3])
    item.focused = true
    quiet = QuietRenderer.new
    expect { item.on_draw(quiet, nil) }.to allocate_nothing
  end
end
