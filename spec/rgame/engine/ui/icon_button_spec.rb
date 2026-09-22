# frozen_string_literal: true

RSpec.describe RGame::Engine::UI::IconButton do
  let(:home) { StubImage.new(50, 50) }
  let(:renderer) { FakeRenderer.new.tap { |r| r.register_image(:home, home) } }
  let(:root) { RGame::Engine::Node2D.new }

  before { RGame::Engine::I18n.load_hash(en: { home: 'Home' }) }

  def button(image: :home, **)
    root.add_node(described_class.new(image: image, width: 64, height: 80, **))
        .tap { root.enter_tree }
  end

  def draw
    renderer.clear
    root.draw(renderer, screen_view)
    renderer.calls.reject { |call| call.name == :translated }
  end

  def drawn_image = draw.find { |call| call.name == :image }

  def in_state(state, **)
    item = button(enabled: state != :disabled, **)
    item.focused = state == :focused
    item.press if state == :pressed
    item
  end

  describe 'where it draws' do
    it 'centres the image on the slot with no label' do
      button
      expect(drawn_image.args).to eq([home, 32.0, 40.0])
    end

    # FakeRenderer measures with the shipped typeface, 18 pixels a line.
    describe 'with a caption' do
      def centred(text) = (64 - RGame::Util::Typeface.default.text_width(text)) / 2

      it 'centres the image in the space above the caption' do
        button(label: 'home')
        expect(drawn_image.args).to eq([home, 32.0, 31.0])
      end

      it 'centres the caption along the bottom edge, inside the slot' do
        button(label: 'home')
        expect(draw.last.args).to eq(['Home', centred('Home'), 62])
      end

      it 'draws the caption in the current locale' do
        RGame::Engine::I18n.load_hash(de: { home: 'Zuhause' })
        button(label: 'home')
        RGame::Engine::I18n.locale = :de
        expect(draw.last.args).to eq(['Zuhause', centred('Zuhause'), 62])
      end
    end
  end

  describe 'following its state' do
    %i[idle focused pressed disabled].each do |state|
      it "tints and scales for #{state}" do
        in_state(state, scales: described_class::SCALES.merge(state => 2))
        expect(drawn_image.options.slice(:color, :scale))
          .to eq(color: described_class::TINTS.fetch(state), scale: 2)
      end
    end

    it 'coerces tints given as arrays' do
      in_state(:idle, tints: described_class::TINTS.merge(idle: [1, 2, 3]))
      expect(drawn_image.options[:color]).to eq(RGame::Util::Color.new(1, 2, 3))
    end

    it 'draws its caption in the disabled colour while disabled' do
      in_state(:disabled, label: 'home')
      expect(draw.last.options[:color]).to eq(RGame::Engine::UI::TextButton::DISABLED_LABEL_COLOR)
    end
  end

  describe 'an image that is not there' do
    # An entry whose art is not in yet still says what it is.
    it 'draws only the caption for image: nil' do
      button(image: nil, label: 'home')
      expect(draw.map(&:name)).to eq(%i[text])
    end

    # Not the same case: a typo in an id is a mistake, and the renderer says so.
    it 'raises on the first draw for an id nobody registered' do
      button(image: :hoem)
      expect { draw }.to raise_error(KeyError, /hoem/)
    end
  end

  describe 'building one' do
    it 'refuses tints with a state missing, naming it' do
      expect { described_class.new(image: :home, tints: described_class::TINTS.except(:pressed)) }
        .to raise_error(KeyError, /pressed/)
    end

    it 'refuses scales with a state missing, naming it' do
      expect { described_class.new(image: :home, scales: described_class::SCALES.except(:disabled)) }
        .to raise_error(KeyError, /disabled/)
    end
  end

  describe 'the style' do
    it 'has none by default' do
      button
      expect(draw.map(&:name)).to eq(%i[image])
    end

    it 'is drawn first, and below the image and caption' do
      button(label: 'home', style: RGame::Engine::UI::ShapeStyle.new(shape: :disc)).focused = true
      calls = draw
      style_calls, content = calls.partition { |call| call.name == :circle }
      expect([calls.first.name, style_calls.map { |c| c.options[:z] }.max < content.map { |c| c.options[:z] }.min])
        .to eq([:circle, true])
    end

    describe 'naming a content colour' do
      let(:disc) { RGame::Engine::UI::ShapeStyle.new(shape: :disc) }
      let(:dark) { RGame::Engine::UI::ShapeStyle::CONTENT[:pressed] }

      # The measured bug: both defaults are gold, so a pressed icon on a disc
      # was drawn gold on gold and could not be seen.
      it "tints the image in the style's colour while pressed" do
        in_state(:pressed, style: disc)
        expect(drawn_image.options[:color]).to eq(dark)
      end

      # The caption is under the style rather than on its fill, so what reads
      # on the fill is not what reads under it.
      it "keeps the caption in its own colour, not the style's, while pressed" do
        in_state(:pressed, style: disc, label: 'home')
        expect(draw.last.options[:color]).to eq(RGame::Engine::UI::TextButton::LABEL_COLOR)
      end

      it 'keeps its own tint in a state the style leaves nil' do
        in_state(:focused, style: disc)
        expect(drawn_image.options[:color]).to eq(described_class::TINTS[:focused])
      end

      it 'keeps its own pressed tint with no style' do
        in_state(:pressed)
        expect(drawn_image.options[:color]).to eq(described_class::TINTS[:pressed])
      end

      it 'keeps its own pressed tint on a style that answers only draw' do
        plain = Class.new { def draw(_renderer, _state, _width, _height) = nil }.new
        in_state(:pressed, style: plain)
        expect(drawn_image.options[:color]).to eq(described_class::TINTS[:pressed])
      end
    end

    it 'is handed the state and the slot' do
      style = instance_double(RGame::Engine::UI::ShapeStyle, draw: nil)
      in_state(:pressed, style: style)
      draw
      expect(style).to have_received(:draw).with(renderer, :pressed, 64, 80)
    end

    # FakeRenderer's lines are 18 pixels, so the style gets 80 - 18.
    it 'is handed only the space above a caption' do
      style = instance_double(RGame::Engine::UI::ShapeStyle, draw: nil)
      in_state(:pressed, style: style, label: 'home')
      draw
      expect(style).to have_received(:draw).with(renderer, :pressed, 64, 62)
    end

    it 'puts the disc round the picture, with the caption below it' do
      in_state(:focused, style: RGame::Engine::UI::ShapeStyle.new(shape: :disc), label: 'home')
      calls = draw
      disc = calls.find { |call| call.name == :circle }
      caption = calls.find { |call| call.name == :text }
      expect([disc.args[1], disc.args[1] + disc.args[2]]).to eq([drawn_image.args[2], caption.args[2]])
    end
  end

  describe 'allocation' do
    let(:quiet) { QuietRenderer.new }

    it 'draws without allocating' do
      item = in_state(:focused, style: RGame::Engine::UI::ShapeStyle.new(shape: :disc))
      expect { item._draw(quiet, nil) }.to allocate_nothing
    end

    it 'draws pressed on a style naming a content colour without allocating' do
      item = in_state(:pressed, label: 'home', style: RGame::Engine::UI::ShapeStyle.new(shape: :disc))
      expect { item._draw(quiet, nil) }.to allocate_nothing
    end

    it 'draws captioned without allocating' do
      item = in_state(:disabled, label: 'home', tints: described_class::TINTS.merge(idle: [1, 2, 3]))
      expect { item._draw(quiet, nil) }.to allocate_nothing
    end
  end
end
