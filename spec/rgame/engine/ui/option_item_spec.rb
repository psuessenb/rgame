# frozen_string_literal: true

RSpec.describe RGame::Engine::UI::OptionItem do
  let(:slices) { described_class::STYLE.values.to_h { |id| [id, recorder] } }

  let(:renderer) do
    FakeRenderer.new.tap { |r| slices.each { |id, slice| r.register_nine_slice(id, slice) } }
  end
  let(:root) { RGame::Engine::Node2D.new }

  # The same stand-in menu_item_spec uses: FakeRenderer hands a nine-slice draw
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

  def option(**)
    root.add_node(described_class.new(label: 'Volume', width: 240, height: 40,
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
      item = root.add_node(described_class.new(label: 'None', width: 10, height: 10, values: []))
      root.enter_tree
      expect([item.value, item.adjust(1)]).to eq([nil, nil])
    end
  end

  describe 'moving through the list' do
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
    it 'draws the label and the caption for the current value' do
      option(index: 1)
      expect(texts).to include('Volume', '50')
    end

    # `display` turns a value into its caption, and is called for the whole list
    # once in the constructor — a caption built inside `draw` would allocate a
    # String every frame for every row on screen.
    it 'draws captions made by display rather than the values themselves' do
      root.add_node(described_class.new(label: 'Volume', width: 240, height: 40,
                                        values: [0, 50], index: 1,
                                        display: ->(v) { "#{v}%" }))
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

    # Inherited whole from MenuItem: a settings row is focused, pressed or
    # disabled exactly as any other row is.
    it 'draws the disabled element when it is disabled' do
      option(enabled: false)
      root.draw(renderer, screen_view)
      drawn = slices.select { |_id, slice| slice.received.any? }.keys
      expect(drawn).to eq([described_class::STYLE.fetch(:disabled)])
    end
  end
end
