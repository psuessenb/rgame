# frozen_string_literal: true

module RGame
  module Engine
    module UI
      # A menu row whose value is chosen from a list, moved with `ui_left` and
      # `ui_right`.
      #
      #   quality = menu.add(UI::OptionButton.new(label: 'shadows', values: %i[off low high]))
      #   quality.on_changed { |value| settings.shadows = value }
      #
      # It draws `Label        < value >`, and the chevrons appear only where
      # there is somewhere to go — which is the only feedback a player gets that
      # they have reached an end of the list.
      #
      # ## Values move by clamping, while focus wraps
      #
      # `Menu` wraps focus at the ends, and this deliberately does not. A list of
      # menu buttons has no magnitude, so joining its ends only makes a short list
      # quicker to get around. A list of *values* usually does have one — volume,
      # difficulty, a resolution — and wrapping turns "one louder" at the top of
      # the range into silence. Every settings screen a player has used clamps,
      # so this does too.
      #
      # ## A caption is a key, unless it is a Text
      #
      # `display` turns a value into what is drawn for it: a key, which the
      # button makes an Engine::Text of under its `label_scope` just as it does
      # the label, or a `Text`, used as it is. The default makes a Symbol value
      # its own key and anything else a literal, so `%i[off low high]` reads
      # the keys `off`, `low` and `high`, and `[0, 50, 100]` draws the numbers:
      #
      #   UI::OptionButton.new(label: 'volume', values: [0, 50, 100],
      #                        display: ->(percent) { Engine::Text.literal("#{percent}%") })
      #
      # `display` is called for the whole list in the constructor. Doing it in
      # `on_draw` instead would allocate a String every frame for every row on
      # screen, which is what `Game/NoInterpolationInHotPath` refuses — and the
      # values themselves are what a game acts on, so they cannot simply be
      # stored as text.
      #
      # A caption `Text` with variables shows the values its last `with` was
      # given, as a label does.
      #
      # The value column is as wide as the widest caption. It is measured again
      # whenever any caption's String changes — a locale switch, a new scope, a
      # `with` with new values — which a draw notices by object identity, so a
      # switch to longer captions widens it and an unchanged draw measures
      # nothing.
      class OptionButton < PanelButton
        # Emits the newly selected value, which is the only thing a listener
        # wants; `index` is available on the button for anything that needs it.
        signal :on_changed, Signal.define(:value)

        LEFT_CHEVRON = '<'
        RIGHT_CHEVRON = '>'

        PADDING = 12
        GAP = 8

        DISPLAY = ->(value) { value.is_a?(Symbol) ? value : Text.literal(value.to_s) }

        def initialize(label:, values:, index: 0, display: DISPLAY, **)
          super(label: label, **)
          @values = values.to_a.freeze
          shown = @values.map { |value| display.call(value) }
          @captions = shown.map { |caption| text_for(caption) }.freeze
          @keyed_captions = @captions.reject.with_index { |_caption, at| shown[at].is_a?(Text) }.freeze
          @measured = Array.new(@captions.size)
          @index = @values.empty? ? 0 : index.clamp(0, @values.size - 1)
        end

        attr_reader :values, :index

        def value = @values[@index]

        # The Engine::Text drawn for the current value, or nil for an empty list.
        def caption = @captions[@index]

        # Scopes the captions `display` gave as keys along with the label.
        def label_scope=(scope)
          super
          @keyed_captions.each { |caption| caption.scope = label_scope }
        end

        # Selects `value` if the list holds it, and says whether it did. A game
        # restoring a saved setting does not have to know where in the list it
        # sits, and a value that is no longer offered — an old save, a list that
        # changed between versions — leaves the button where it was rather than
        # raising.
        def value=(value)
          found = @values.index(value)
          @index = found if found
        end

        # Moves the selection by `delta`, clamped. Returns the button when it
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

        private

        def draw_foreground(renderer)
          y = label_y(renderer)
          color = current_label_color
          renderer.text(@label, PADDING, y, z: 1, color: color) if @label
          draw_value(renderer, y, color)
        end

        def draw_value(renderer, y, color)
          return if @values.empty?

          chevron = renderer.text_width(RIGHT_CHEVRON)
          right = width - PADDING - chevron
          column = column_width(renderer)
          left = right - GAP - column - GAP - chevron

          renderer.text(LEFT_CHEVRON, left, y, z: 1, color: color) if @index.positive?
          renderer.text(RIGHT_CHEVRON, right, y, z: 1, color: color) if @index < @values.size - 1

          text = caption.to_s
          centred = left + chevron + GAP + ((column - renderer.text_width(text)) / 2)
          renderer.text(text, centred, y, z: 1, color: color)
        end

        def column_width(renderer)
          return @column_width if captions_measured?

          @column_width = 0
          @captions.each_with_index do |caption, at|
            @measured[at] = caption.to_s
            width = renderer.text_width(@measured[at])
            @column_width = width if width > @column_width
          end
          @column_width
        end

        def captions_measured?
          at = 0
          while at < @captions.size
            return false unless @captions[at].to_s.equal?(@measured[at])

            at += 1
          end
          true
        end
      end
    end
  end
end
