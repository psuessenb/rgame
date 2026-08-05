# frozen_string_literal: true

module Engine
  module UI
    # A focusable picker that cycles through `options` (each an [value, label] pair).
    # While focused it responds to the keyboard/controller (ui_left/ui_right) and to a
    # click in its left/right half; it ignores up/down and confirm, so it coexists with
    # a Menu's vertical navigation. Shows the current label between `<` `>` arrows on a
    # 9-slice background (reusing the button atlas). Emits on_changed(index, value) — a
    # multi-field signal (Signal.define(:index, :value)), so the listener gets both the
    # ordinal and the selected value without a shared event object to allocate.
    class Selector < Control
      ARROW_LEFT  = '<'
      ARROW_RIGHT = '>'
      LABEL_COLOR = [60, 42, 28].freeze
      IDLE_TEXTURE  = :button_idle
      FOCUS_TEXTURE = :button_focus
      ARROW_INSET = 14 # px from each edge to the arrow

      attr_reader :index

      signal :on_changed, Signal.define(:index, :value)

      def initialize(parent, x:, y:, width:, height:, options:, index: 0, z: 0, enabled: true)
        super(parent, x: x, y: y, width: width, height: height, z: z, enabled: enabled)
        @options = options
        @index = index
        @label_width = nil # measured once per value, then cached
      end

      def value = @options[@index][0]
      def label = @options[@index][1]

      def update(_dt, actions)
        return unless @enabled && @focused

        cycle(-1) if actions.pressed?(:ui_left)
        cycle(+1) if actions.pressed?(:ui_right)
        return unless actions.pressed?(:ui_click) && contains?(actions.pointer_x, actions.pointer_y)

        cycle(actions.pointer_x < @abs_x + (@width / 2) ? -1 : +1)
      end

      def draw(renderer)
        renderer.nine_slice(@focused ? FOCUS_TEXTURE : IDLE_TEXTURE, @abs_x, @abs_y, @width, @height, z: @abs_z)
        y = @abs_y + ((@height - renderer.text_height) / 2)
        @label_width ||= renderer.text_width(label)

        renderer.text(ARROW_LEFT, @abs_x + ARROW_INSET, y, z: @abs_z + 1, color: LABEL_COLOR)
        renderer.text(ARROW_RIGHT, @abs_x + @width - ARROW_INSET - renderer.text_width(ARROW_RIGHT), y,
                      z: @abs_z + 1, color: LABEL_COLOR)
        renderer.text(label, @abs_x + ((@width - @label_width) / 2), y, z: @abs_z + 1, color: LABEL_COLOR)
      end

      private

      def cycle(step)
        @index = (@index + step) % @options.size
        @label_width = nil
        on_changed_signal.emit(index: @index, value: value)
      end
    end
  end
end
