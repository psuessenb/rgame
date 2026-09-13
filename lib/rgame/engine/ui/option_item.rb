# frozen_string_literal: true

module RGame
  module Engine
    module UI
      # A menu row whose value is chosen from a list, moved with `ui_left` and
      # `ui_right`.
      #
      #   quality = menu.add_option('Shadows', values: %i[off low high])
      #   quality.on_changed { |value| settings.shadows = value }
      #
      # It draws `Label        < value >`, and the chevrons appear only where
      # there is somewhere to go — which is the only feedback a player gets that
      # they have reached an end of the list.
      #
      # ## Values move by clamping, while focus wraps
      #
      # `Menu` wraps focus at the ends, and this deliberately does not. A list of
      # menu items has no magnitude, so joining its ends only makes a short list
      # quicker to get around. A list of *values* usually does have one — volume,
      # difficulty, a resolution — and wrapping turns "one louder" at the top of
      # the range into silence. Every settings screen a player has used clamps,
      # so this does too.
      #
      # ## The captions are built once, not per frame
      #
      # `display` turns a value into the text drawn for it, and it is called for
      # the whole list in the constructor. Doing it in `on_draw` instead would
      # allocate a String every frame for every row on screen, which is what
      # `Game/NoInterpolationInHotPath` refuses — and the values themselves are
      # what a game acts on, so they cannot simply be stored as text.
      class OptionItem < MenuItem
        # Emits the newly selected value, which is the only thing a listener
        # wants; `index` is available on the item for anything that needs it.
        signal :on_changed, Signal.define(:value)

        LEFT_CHEVRON = '<'
        RIGHT_CHEVRON = '>'

        PADDING = 12
        GAP = 8

        def initialize(label:, values:, index: 0, display: :to_s.to_proc, **)
          super(label: label, **)
          @values = values.to_a.freeze
          @captions = @values.map { |value| display.call(value).to_s.freeze }.freeze
          @index = @values.empty? ? 0 : index.clamp(0, @values.size - 1)
        end

        attr_reader :values, :index

        def value = @values[@index]
        def caption = @captions[@index]

        # Selects `value` if the list holds it, and says whether it did. A game
        # restoring a saved setting does not have to know where in the list it
        # sits, and a value that is no longer offered — an old save, a list that
        # changed between versions — leaves the item where it was rather than
        # raising.
        def value=(value)
          found = @values.index(value)
          @index = found if found
        end

        # Moves the selection by `delta`, clamped. Returns the item when it
        # actually moved and nil otherwise, so a caller can tell "pressed at the
        # end of the list" from "changed" without comparing values.
        #
        # Disabled and empty are both nil for the same reason `activate` is:
        # a caller never has to check first.
        def adjust(delta)
          return nil unless enabled?
          return nil if @values.empty?

          moved = (@index + delta).clamp(0, @values.size - 1)
          return nil if moved == @index

          @index = moved
          on_changed_signal.emit(value)
          self
        end

        def on_draw(renderer, _view)
          renderer.nine_slice(@style.fetch(state), 0, 0, width, height)

          y = label_y(renderer)
          color = enabled? ? LABEL_COLOR : DISABLED_LABEL_COLOR
          renderer.text(@label, PADDING, y, z: 1, color: color)
          draw_value(renderer, y, color)
        end

        private

        def draw_value(renderer, y, color)
          return if @values.empty?

          chevron = renderer.text_width(RIGHT_CHEVRON)
          right = width - PADDING - chevron
          column = column_width(renderer)
          left = right - GAP - column - GAP - chevron

          renderer.text(LEFT_CHEVRON, left, y, z: 1, color: color) if @index.positive?
          renderer.text(RIGHT_CHEVRON, right, y, z: 1, color: color) if @index < @values.size - 1

          text = caption
          centred = left + chevron + GAP + ((column - renderer.text_width(text)) / 2)
          renderer.text(text, centred, y, z: 1, color: color)
        end

        def column_width(renderer)
          @column_width ||= @captions.map { |text| renderer.text_width(text) }.max
        end
      end
    end
  end
end
