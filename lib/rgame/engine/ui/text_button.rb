# frozen_string_literal: true

module RGame
  module Engine
    module UI
      # A label centred on a style: the button to build a menu with before any
      # art exists, and the base of every shipped button that draws a label.
      #
      #   menu.add(UI::TextButton.new(label: 'play')).on_activated { start }
      #   menu.add(UI::TextButton.new(label: 'credits', style: UI::ShapeStyle.new(outline: nil)))
      #   menu.add(UI::TextButton.new(label: 'quit', style: nil))
      #
      # With no `style:` it draws UI::ShapeStyle::DEFAULT, which needs nothing
      # registered with the renderer. `style: nil` draws the label alone. The
      # style draws at `z: 0` or below and the label at `z: 1`, so the label is
      # always on top. Focus, pressing and activation are all UI::Button's.
      #
      # The label colours are coerced once, so a draw allocates nothing. A style
      # answering `content_color(state)` —
      # UI::ShapeStyle does — overrides them in any state it names, because what
      # reads on a fill is the style's to say: a light label on a gold pressed
      # fill would all but disappear. A subclass that draws more than a label —
      # UI::OptionButton — overrides `draw_foreground`, and so keeps its style
      # without having to remember to draw it.
      class TextButton < Button
        LABEL_COLOR = Util::Color.new(240, 236, 224)
        DISABLED_LABEL_COLOR = Util::Color.new(120, 116, 128)

        sealed_reader :style, :label_color, :disabled_label_color

        def initialize(label:, style: ShapeStyle::DEFAULT, label_color: LABEL_COLOR,
                       disabled_label_color: DISABLED_LABEL_COLOR, **)
          super(label: label, **)
          @rgame_style = style
          @rgame_style_names_content = style.respond_to?(:content_color)
          @rgame_label_color = Util::Color.coerce(label_color)
          @rgame_disabled_label_color = Util::Color.coerce(disabled_label_color)
        end

        def _draw(renderer, _view)
          @rgame_style&.draw(renderer, state, width, height)
          draw_foreground(renderer)
        end

        private

        def draw_foreground(renderer)
          text = @rgame_label.to_s
          renderer.text(text, centred_x(renderer, text), label_y(renderer), z: 1, color: current_label_color)
        end

        def current_label_color
          style_content_color || (@rgame_enabled ? @rgame_label_color : @rgame_disabled_label_color)
        end

        def style_content_color = @rgame_style_names_content ? @rgame_style.content_color(state) : nil
        def centred_x(renderer, text) = (width - renderer.text_width(text)) / 2
        def label_y(renderer) = (height - renderer.text_height) / 2
      end
    end
  end
end
