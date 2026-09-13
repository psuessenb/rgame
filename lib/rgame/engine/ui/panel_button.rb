# frozen_string_literal: true

module RGame
  module Engine
    module UI
      # A UI::TextButton on a nine-slice: the shipped atlas's button, one element
      # per state, with a dark label.
      #
      #   resume = menu.add(UI::PanelButton.new(label: 'Resume'))
      #   resume.on_activated { cutscene.close }
      #
      #   menu.add(UI::PanelButton.new(label: 'Save game', enabled: false))
      #   menu.add(UI::PanelButton.new(label: 'Load', style: UI::PanelButton::STYLE.with(idle: :mine)))
      #
      # `STYLE` names the element drawn for each state — which is why the shipped
      # atlas has one for each of the four. It differs from a TextButton only in
      # its defaults; every one of them can still be passed.
      class PanelButton < TextButton
        STYLE = NineSliceStyle.new(idle: :button_idle, focused: :button_focus,
                                   pressed: :button_pressed, disabled: :button_disabled)

        LABEL_COLOR = Util::Color.new(46, 34, 24)
        DISABLED_LABEL_COLOR = Util::Color.new(120, 110, 100)

        def initialize(label:, style: STYLE, label_color: LABEL_COLOR,
                       disabled_label_color: DISABLED_LABEL_COLOR, **)
          super
        end
      end
    end
  end
end
