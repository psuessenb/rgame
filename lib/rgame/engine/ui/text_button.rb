# frozen_string_literal: true

module RGame
  module Engine
    module UI
      # A label centred on a style: the button to build a menu with before any
      # art exists, and the base of every shipped button that draws a label.
      #
      #   menu.add(UI::TextButton.new(label: 'Play')).on_activated { start }
      #   menu.add(UI::TextButton.new(label: 'Credits', style: UI::ShapeStyle.new(outline: nil)))
      #   menu.add(UI::TextButton.new(label: 'Quit', style: nil))
      #
      # With no `style:` it draws UI::ShapeStyle::DEFAULT, which needs nothing
      # registered with the renderer. `style: nil` draws the label alone. The
      # style draws at `z: 0` or below and the label at `z: 1`, so the label is
      # always on top. Focus, pressing and activation are all UI::Button's.
      #
      # The label colours are coerced once, so they may be arrays and a draw
      # still allocates nothing. A style answering `content_color(state)` —
      # UI::ShapeStyle does — overrides them in any state it names, because what
      # reads on a fill is the style's to say: a light label on a gold pressed
      # fill would all but disappear. A subclass that draws more than a label —
      # UI::OptionButton — overrides `draw_foreground`, and so keeps its style
      # without having to remember to draw it.
      class TextButton < Button
        LABEL_COLOR = Util::Color.new(240, 236, 224)
        DISABLED_LABEL_COLOR = Util::Color.new(120, 116, 128)

        attr_reader :style, :label_color, :disabled_label_color

        def initialize(label:, style: ShapeStyle::DEFAULT, label_color: LABEL_COLOR,
                       disabled_label_color: DISABLED_LABEL_COLOR, **)
          super(label: label, **)
          @style = style
          @style_names_content = style.respond_to?(:content_color)
          @label_color = Util::Color.coerce(label_color)
          @disabled_label_color = Util::Color.coerce(disabled_label_color)
        end

        def on_draw(renderer, _view)
          @style&.draw(renderer, state, width, height)
          draw_foreground(renderer)
        end

        private

        def draw_foreground(renderer)
          renderer.text(@label, label_x(renderer), label_y(renderer), z: 1, color: current_label_color)
        end

        def current_label_color = style_content_color || (@enabled ? @label_color : @disabled_label_color)
        def style_content_color = @style_names_content ? @style.content_color(state) : nil
        def label_x(renderer) = (width - renderer.text_width(@label)) / 2
        def label_y(renderer) = (height - renderer.text_height) / 2
      end
    end
  end
end
