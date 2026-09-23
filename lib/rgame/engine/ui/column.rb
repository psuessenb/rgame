# frozen_string_literal: true

module RGame
  module Engine
    module UI
      # A Menu layout: buttons stacked downwards from the menu's origin, all the
      # same size, `spacing` pixels apart. A UI::Stack on the vertical axis, so
      # UI::Stepping moves through it with `ui_up` and `ui_down`.
      #
      #   UI::Menu.new(layout: UI::Column.new(item_width: 220, item_height: 44))
      #
      # It takes no `axis:` — a column that is not vertical is a UI::Row.
      # `visible_rows:` shows that many buttons at a time, and the menu scrolls
      # the rest into view.
      class Column < Stack
        def initialize(item_width:, item_height:, spacing: 8, visible_rows: nil)
          super(axis: :vertical, item_width: item_width, item_height: item_height, spacing: spacing,
                visible_rows: visible_rows)
        end
      end
    end
  end
end
