# frozen_string_literal: true

RSpec.describe RGame::Engine::UI::RadialMenu do
  let(:root) { RGame::Engine::Node2D.new }
  let(:renderer) { FakeRenderer.new }

  # One reused snapshot over hashes shifted in place, the way ActionMapper
  # builds it.
  let(:snapshot) do
    axes = { ui_radial_x: 0.0, ui_radial_y: 0.0 }
    actions = RGame::Engine::Actions.new(held: { ui_confirm: false }, axes: axes, prev_held: { ui_confirm: false })

    lambda do |x, y|
      axes[:ui_radial_x] = x
      axes[:ui_radial_y] = y
      actions
    end
  end

  def wheel(**) = root.add_node(described_class.new(radius: 150, button_width: 96, button_height: 30, **))

  before { RGame::Engine::I18n.load_hash(en: { x: 'x' }) }

  def button = RGame::Engine::UI::TextButton.new(label: 'x', style: nil)

  def aim(x, y) = root.control(snapshot.call(x, y))

  def draw
    root.enter_tree
    renderer.clear
    root.draw(renderer, screen_view)
    renderer.calls
  end

  describe 'what it is built from' do
    it 'refuses a layout:, which would replace its ring' do
      layout = RGame::Engine::UI::Column.new(item_width: 1, item_height: 1)
      expect { described_class.new(radius: 150, button_width: 64, layout: layout) }
        .to raise_error(ArgumentError, /layout: and navigation:/)
    end

    it 'refuses a navigation:, which would replace its pointing' do
      expect { described_class.new(radius: 150, button_width: 64, navigation: RGame::Engine::UI::Stepping.new) }
        .to raise_error(ArgumentError, /layout: and navigation:/)
    end

    it 'lays its buttons on a ring of the given radius and sizes' do
      layout = wheel.layout
      expect([layout.class, layout.radius, layout.item_width, layout.item_height])
        .to eq([RGame::Engine::UI::Ring, 150, 96, 30])
    end

    it 'makes square slots when no button_height is given' do
      layout = described_class.new(radius: 100, button_width: 64).layout
      expect([layout.item_width, layout.item_height]).to eq([64, 64])
    end

    it 'gives its pointing no grace window when always open' do
      expect(wheel.navigation.grace).to eq(0.0)
    end

    it 'gives its pointing the default grace window when held open by a trigger' do
      expect(wheel(trigger: :quick).navigation.grace).to eq(RGame::Engine::UI::Pointing::GRACE)
    end

    it 'passes grace: on to its pointing' do
      expect(wheel(trigger: :quick, grace: 0.3).navigation.grace).to eq(0.3)
    end

    it 'focuses by pointing, with the given dead zone' do
      navigation = wheel(dead_zone: 0.3).navigation
      expect([navigation.class, navigation.dead_zone]).to eq([RGame::Engine::UI::Pointing, 0.3])
    end

    it 'still passes other keywords on to the node' do
      expect(wheel(x: 320, y: 240).then { [it.x, it.y] }).to eq([320, 240])
    end
  end

  describe 'drawing' do
    it 'draws the backdrop, the dead zone and the pointer, in that order, before its buttons' do
      menu = wheel
      menu.add(button)
      expect(draw.map(&:name) - %i[translated]).to eq(%i[circle circle line circle text])
    end

    it 'sizes the backdrop from its bounds, plus padding' do
      wheel(padding: 10).add(button)
      expect(draw.first.args).to eq([0, 0, 208.0])
    end

    it 'draws the dead zone to scale' do
      wheel(dead_zone: 0.4).add(button)
      expect(draw[1].args).to eq([0, 0, 60.0])
    end

    it 'draws the backdrop the same size with one button as with eight' do
      menu = wheel
      menu.add(button)
      one = draw.first.args
      7.times { menu.add(button) }
      expect(draw.first.args).to eq(one)
    end

    it 'draws in the colours it was given' do
      wheel(backdrop: [1, 2, 3], dead_zone_color: [4, 5, 6], pointer: [7, 8, 9])
      expect(draw.map { |call| call.options[:color] }.uniq)
        .to eq([RGame::Util::Color.new(1, 2, 3), RGame::Util::Color.new(4, 5, 6), RGame::Util::Color.new(7, 8, 9)])
    end

    describe 'a part set to nil' do
      def backdrop = [:circle, described_class::BACKDROP]
      def dead_zone = [:circle, described_class::DEAD_ZONE]
      def pointer = [[:line, described_class::POINTER], [:circle, described_class::POINTER]]

      def parts = draw.map { |call| [call.name, call.options[:color]] }

      it 'omits the backdrop for backdrop: nil' do
        wheel(backdrop: nil)
        expect(parts).to eq([dead_zone, *pointer])
      end

      it 'omits the dead zone for dead_zone_color: nil' do
        wheel(dead_zone_color: nil)
        expect(parts).to eq([backdrop, *pointer])
      end

      it 'omits the pointer and its tip for pointer: nil' do
        wheel(pointer: nil)
        expect(parts).to eq([backdrop, dead_zone])
      end
    end

    describe 'the pointer' do
      it 'rests at the centre when the stick does' do
        wheel.add(button)
        aim(0.0, 0.0)
        expect(draw[2].args).to eq([0, 0, 0.0, 0.0])
      end

      it 'reaches the ring at full deflection' do
        wheel.add(button)
        aim(1.0, 0.0)
        expect(draw[3].args).to eq([150.0, 0.0, 6])
      end

      it 'is clamped to the ring when the aim is longer than a stick can reach' do
        # Two arrow keys at once read as (1, 1).
        wheel.add(button)
        aim(1.0, 1.0)
        expect(draw[2].args.map { it.round(1) }).to eq([0, 0, 106.1, 106.1])
      end

      it 'is not stretched to the ring below full deflection' do
        wheel.add(button)
        aim(0.2, 0.0)
        expect(draw[3].args.first).to be_within(1e-9).of(30.0)
      end
    end

    it 'allocates nothing with the stick deflected' do
      menu = wheel
      8.times { menu.add(button) }
      aim(0.7, -0.6)
      quiet = QuietRenderer.new
      expect { menu._draw(quiet, nil) }.to allocate_nothing
    end
  end
end
