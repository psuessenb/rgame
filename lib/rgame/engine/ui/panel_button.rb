# frozen_string_literal: true

module RGame
  module Engine
    module UI
      # The shipped button: a label on a nine-slice, one element per state.
      #
      #   resume = menu.add(UI::PanelButton.new(label: 'Resume'))
      #   resume.on_activated { cutscene.close }
      #
      #   menu.add(UI::PanelButton.new(label: 'Save game', enabled: false))
      #
      # It draws `STYLE[state]` — which is why the shipped atlas has an element
      # for each of the four states — and centres its label on top. Focus,
      # pressing and activation are all UI::Button's.
      class PanelButton < Button
        STYLE = {
          idle: :button_idle,
          focused: :button_focus,
          pressed: :button_pressed,
          disabled: :button_disabled
        }.freeze

        LABEL_COLOR = [46, 34, 24].freeze
        DISABLED_LABEL_COLOR = [120, 110, 100].freeze

        def initialize(label:, style: STYLE, **)
          super(label: label, **)
          @style = style
        end

        # The panel and its label share this node's slot, so the only ordering
        # question is which of the two goes on top — and `z: 1` says exactly
        # that, about this button and nothing else in the frame.
        def on_draw(renderer, _view)
          renderer.nine_slice(@style.fetch(state), 0, 0, width, height)
          renderer.text(@label, label_x(renderer), label_y(renderer),
                        z: 1, color: @enabled ? LABEL_COLOR : DISABLED_LABEL_COLOR)
        end

        private

        def label_x(renderer) = (width - renderer.text_width(@label)) / 2
        def label_y(renderer) = (height - renderer.text_height) / 2
      end
    end
  end
end
