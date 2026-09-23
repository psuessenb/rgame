# frozen_string_literal: true

RSpec.describe RGame::Engine::UI::OptionButton do
  let(:slices) { described_class::STYLE.elements.values.to_h { |id| [id, recorder] } }

  let(:renderer) do
    FakeRenderer.new.tap { |r| slices.each { |id, slice| r.register_nine_slice(id, slice) } }
  end
  let(:root) { RGame::Engine::Node2D.new }

  before { RGame::Engine::I18n.load_hash(en: { volume: 'Volume', none: 'None' }) }

  # The same stand-in panel_button_spec uses: FakeRenderer hands a nine-slice draw
  # straight to the registered element, so an element can say it was the one
  # drawn without pretending to be a real nine-slice.
  def recorder
    Class.new do
      attr_reader :received

      def initialize = @received = []
      def method_missing(name, *args, **options) = @received << [name, args, options]
      def respond_to_missing?(*) = true
    end.new
  end

  def option(label: 'volume', **)
    root.add_node(described_class.new(label: label, width: 240, height: 40,
                                      values: [0, 50, 100], **))
        .tap { root.enter_tree }
  end

  # Every string drawn this frame, in the order it was asked for.
  def texts
    root.draw(renderer, screen_view)
    renderer.calls_to(:text).map { |call| call.args.first }
  end

  describe 'the value it holds' do
    it 'starts on the first of the list' do
      expect(option.value).to eq(0)
    end

    it 'starts wherever it was told to' do
      expect(option(index: 2).value).to eq(100)
    end

    # A list that changed between versions, or an index typed by hand, is not
    # worth raising over — there is always a value to draw.
    it 'clamps a starting index past the end' do
      expect(option(index: 9).value).to eq(100)
    end

    it 'is empty-safe' do
      item = root.add_node(described_class.new(label: 'none', width: 10, height: 10, values: []))
      root.enter_tree
      expect([item.value, item.adjust(1)]).to eq([nil, nil])
    end
  end

  describe 'moving through the list' do
    # A focus group crosses on a direction the focused button cannot adjust. An
    # OptionButton answers nil at the end of its values, and still adjusts.
    it 'is adjustable, even at the end of its values' do
      item = option
      item.value = 100
      expect([item.adjust(1), item.adjustable?]).to eq([nil, true])
    end

    it 'moves one step at a time' do
      item = option
      item.adjust(1)
      expect(item.value).to eq(50)
    end

    it 'reports the item when it moved' do
      item = option
      expect(item.adjust(1)).to be(item)
    end

    it 'emits the new value' do
      item = option
      seen = nil
      item.on_changed { |value| seen = value }
      item.adjust(1)
      expect(seen).to eq(50)
    end

    # Focus wraps because a list of items has no magnitude. A list of *values*
    # usually does, and wrapping would turn "one louder" at the top of a volume
    # range into silence.
    describe 'the ends of the list' do
      it 'clamps rather than wrapping at the top' do
        item = option(index: 2)
        expect([item.adjust(1), item.value]).to eq([nil, 100])
      end

      it 'clamps rather than wrapping at the bottom' do
        item = option
        expect([item.adjust(-1), item.value]).to eq([nil, 0])
      end

      # nil rather than the item, so a caller can tell "pressed at the end" from
      # "changed" without comparing values.
      it 'emits nothing when it did not move' do
        item = option
        fired = false
        item.on_changed { fired = true }
        item.adjust(-1)
        expect(fired).to be(false)
      end
    end

    # The same refusal `activate` makes, for the same reason: a caller never has
    # to check first.
    it 'refuses while disabled' do
      item = option(enabled: false)
      fired = false
      item.on_changed { fired = true }
      expect([item.adjust(1), item.value, fired]).to eq([nil, 0, false])
    end
  end

  # A game restoring a saved setting knows the value, not where it sits.
  describe 'selecting by value' do
    it 'finds the value in the list' do
      item = option
      item.value = 100
      expect(item.index).to eq(2)
    end

    # An old save, or a list that changed between versions. There is nothing
    # better to do than leave it where it is.
    it 'ignores a value the list does not offer' do
      item = option(index: 1)
      item.value = 75
      expect(item.value).to eq(50)
    end

    it 'does not emit, because nothing chose it' do
      item = option
      fired = false
      item.on_changed { fired = true }
      item.value = 100
      expect(fired).to be(false)
    end
  end

  describe 'what it draws' do
    it "draws label, chevrons and value in a shape style's content colour while pressed" do
      option(index: 1, style: RGame::Engine::UI::ShapeStyle::DEFAULT).press
      root.draw(renderer, screen_view)
      expect(renderer.calls_to(:text).map { |call| call.options[:color] }.uniq)
        .to eq([RGame::Engine::UI::ShapeStyle::CONTENT[:pressed]])
    end

    it 'draws the label and the caption for the current value' do
      option(index: 1)
      expect(texts).to include('Volume', '50')
    end

    # `display` turns a value into its caption, and is called for the whole list
    # once in the constructor — a caption built inside `draw` would allocate a
    # String every frame for every row on screen.
    it 'draws only the value without a label' do
      option(label: nil, index: 1)
      expect(texts).to eq(['<', '>', '50'])
    end

    it 'draws captions made by display rather than the values themselves' do
      root.add_node(described_class.new(label: 'volume', width: 240, height: 40,
                                        values: [0, 50], index: 1,
                                        display: ->(v) { RGame::Engine::Text.literal("#{v}%") }))
      root.enter_tree
      expect(texts).to include('50%')
    end

    describe 'the chevrons' do
      it 'shows both while there is somewhere to go either way' do
        option(index: 1)
        expect(texts).to include('<', '>')
      end

      it 'hides the left one at the bottom of the list' do
        option(index: 0)
        expect(texts).not_to include('<')
      end

      it 'hides the right one at the top' do
        option(index: 2)
        expect(texts).not_to include('>')
      end
    end

    it 'draws its text above the element behind it' do
      option
      root.draw(renderer, screen_view)
      expect(renderer.calls_to(:text).map { |call| call.options[:z] }).to all(be > 0)
    end

    # Inherited whole from PanelButton: a settings row is focused, pressed or
    # disabled exactly as any other row is.
    it 'draws the disabled element when it is disabled' do
      option(enabled: false)
      root.draw(renderer, screen_view)
      drawn = slices.select { |_id, slice| slice.received.any? }.keys
      expect(drawn).to eq([described_class::STYLE.elements.fetch(:disabled)])
    end
  end

  describe 'captions' do
    let(:i18n) { RGame::Engine::I18n }

    before do
      i18n.load_hash(en: { shadows: 'Shadows', low: 'Lo', high: 'Hi', settings: { low: 'Low', high: 'High' } },
                     de: { low: 'Niedrig', high: 'Hoch' })
    end

    def shadows(**)
      root.add_node(described_class.new(label: 'shadows', width: 240, height: 40, values: %i[low high], **))
          .tap { root.enter_tree }
    end

    # How much wider the widest of `after` measures than the widest of `before`,
    # in the shipped typeface FakeRenderer measures with.
    def growth(before, after)
      face = RGame::Util::Typeface.default
      after.map { face.text_width(it) }.max - before.map { face.text_width(it) }.max
    end

    def left_chevron_x
      renderer.clear
      root.draw(renderer, screen_view)
      renderer.calls_to(:text).find { |call| call.args.first == '<' }&.args&.[](1)
    end

    it 'reads a Symbol value as its own key by default' do
      shadows(index: 1)
      expect(texts).to include('Hi')
    end

    it 'draws any other value as it is by default, in every locale' do
      option(index: 1)
      i18n.locale = :de
      expect(texts).to include('50')
    end

    it 'reads a String display returns as a key' do
      shadows(display: ->(value) { value == :low ? 'high' : 'low' })
      expect(texts).to include('Hi')
    end

    it 'is the Text drawn for the current value' do
      expect(shadows(index: 1).caption.key).to eq('high')
    end

    it 'redraws the caption in a new locale' do
      shadows(index: 1)
      i18n.locale = :de
      expect(texts).to include('Hoch')
    end

    # The left chevron moves left by as much as the widest caption grew.
    it 'measures the value column again after a switch to longer captions' do
      shadows(index: 1)
      english = left_chevron_x
      i18n.locale = :de
      expect(english - left_chevron_x).to be_within(1e-9).of(growth(%w[Lo Hi], %w[Niedrig Hoch]))
    end

    it 'narrows the value column again after a switch back' do
      shadows(index: 1)
      english = left_chevron_x
      i18n.locale = :de
      left_chevron_x
      i18n.locale = :en
      expect(left_chevron_x).to eq(english)
    end

    it "takes the menu's scope for captions display gave as keys" do
      column = RGame::Engine::UI::Column.new(item_width: 240, item_height: 40)
      menu = root.add_node(RGame::Engine::UI::Menu.new(layout: column, scope: 'settings'))
      i18n.load_hash(en: { settings: { shadows: 'Shadows' } })
      menu.add(described_class.new(label: 'shadows', values: %i[low high], index: 1))
      root.enter_tree
      expect(texts).to include('Shadows', 'High')
    end

    it 'measures the column again when the scope changes' do
      i18n.load_hash(en: { settings: { shadows: 'Shadows' } })
      item = shadows(index: 1)
      short = left_chevron_x
      item.label_scope = 'settings'
      expect(short - left_chevron_x).to be_within(1e-9).of(growth(%w[Lo Hi], %w[Low High]))
    end

    it 'keeps a Text display gave as it is under a scope' do
      item = shadows(display: ->(value) { RGame::Engine::Text.new(value, scope: 'settings') })
      item.label_scope = 'elsewhere'
      expect(item.caption.scope).to eq('settings')
    end

    describe 'with variables' do
      before { i18n.load_hash(en: { slot: 'Slot %{n}' }) }

      def slots(captions, **)
        root.add_node(described_class.new(label: 'shadows', width: 240, height: 40, values: %i[low high],
                                          display: ->(value) { captions.fetch(value) }, **))
            .tap { root.enter_tree }
      end

      let(:captions) { { low: RGame::Engine::Text.new('slot', :n), high: RGame::Engine::Text.new('slot', :n) } }

      it 'draws the values the last with gave' do
        captions[:low].with(n: 1)
        captions[:high].with(n: 2)
        slots(captions, index: 1)
        expect(texts).to include('Slot 2')
      end

      # The column grows with no locale switch at all.
      it 'measures the column again when a with changes a caption' do
        captions[:low].with(n: 1)
        captions[:high].with(n: 2)
        slots(captions, index: 1)
        before_with = left_chevron_x
        captions[:low].with(n: 1000)
        expect(before_with - left_chevron_x)
          .to be_within(1e-9).of(growth(['Slot 1', 'Slot 2'], ['Slot 1000', 'Slot 2']))
      end

      it 'draws without allocating while no caption changed' do
        captions[:low].with(n: 1)
        captions[:high].with(n: 2)
        item = slots(captions, index: 1)
        quiet = QuietRenderer.new
        item._draw(quiet, nil)
        expect { item._draw(quiet, nil) }.to allocate_nothing
      end
    end

    it 'draws without allocating after a switch has been drawn once' do
      item = shadows(index: 1)
      quiet = QuietRenderer.new
      item._draw(quiet, nil)
      i18n.locale = :de
      item._draw(quiet, nil)
      expect { item._draw(quiet, nil) }.to allocate_nothing
    end
  end

  # Label, two chevrons and a value: four colours a draw, all built once.
  describe 'allocation' do
    let(:quiet) { QuietRenderer.new }

    it 'draws with both chevrons without allocating' do
      subject_item = option(index: 1)
      expect { subject_item._draw(quiet, nil) }.to allocate_nothing
    end

    it 'draws disabled without allocating' do
      subject_item = option(index: 1, enabled: false)
      expect { subject_item._draw(quiet, nil) }.to allocate_nothing
    end
  end
end
