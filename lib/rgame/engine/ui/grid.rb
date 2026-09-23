# frozen_string_literal: true

module RGame
  module Engine
    module UI
      # A Menu layout: buttons in rows of `columns` slots, filled left to right
      # and top to bottom from the menu's origin, all the same size and
      # `spacing` pixels apart — a bag, a shop's shelves, a skill tree's page.
      #
      #   UI::Menu.new(layout: UI::Grid.new(columns: 4, item_width: 64, item_height: 64, spacing: 6))
      #
      # A UI::Stack whose rows hold `columns` slots, so it places buttons with
      # the arithmetic that places a UI::Column's and a UI::Row's. Its bounds
      # enclose the rows it uses: a grid holding fewer buttons than `columns` is
      # as wide as those buttons.
      #
      # Its `axis` is `:horizontal`, the order it fills in. UI::Stepping reads
      # `columns` and moves along a row with `ui_left` and `ui_right`, and along
      # a column with `ui_up` and `ui_down`. Nothing in a grid is adjusted. It
      # takes no `axis:`, because a grid filled in columns would step the other
      # way round from every other grid.
      class Grid < Stack
        attr_reader :columns

        # Raises ArgumentError unless `columns` is a positive Integer.
        def initialize(columns:, item_width:, item_height:, spacing: 8)
          unless columns.is_a?(Integer) && columns.positive?
            raise ArgumentError, "columns: must be a positive Integer, not #{columns.inspect}"
          end

          super(axis: :horizontal, item_width: item_width, item_height: item_height, spacing: spacing)
          @columns = columns
        end

        private

        def row_length(_count) = @columns
      end
    end
  end
end
