# frozen_string_literal: true

module RGame
  module Engine
    module UI
      # A Menu layout: buttons side by side rightwards from the menu's origin,
      # all the same size, `spacing` pixels apart — a skill bar, a row of tabs.
      # A UI::Stack on the horizontal axis, so the default UI::Stepping moves
      # through it with `ui_left` and `ui_right`, with nothing else said.
      #
      #   UI::Menu.new(layout: UI::Row.new(item_width: 64, item_height: 64))
      #
      # It takes no `axis:` — a row that is not horizontal is a UI::Column.
      class Row < Stack
        def initialize(item_width:, item_height:, spacing: 8)
          super(axis: :horizontal, item_width: item_width, item_height: item_height, spacing: spacing)
        end
      end
    end
  end
end
