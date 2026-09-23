# frozen_string_literal: true

module RGame
  module Engine
    module UI
      # A Menu layout: buttons in a line from the menu's origin, all the same
      # size, `spacing` pixels apart — downwards along the `:vertical` axis,
      # rightwards along the `:horizontal` one. UI::Column and UI::Row are this
      # with the axis fixed, and are what a game builds.
      #
      # A layout is anything that answers `arrange(buttons)` by setting each
      # button's position and size, relative to the menu, `bounds(buttons)` with
      # the rectangle that encloses them, and `axis` — the direction UI::Stepping
      # moves focus along unless told otherwise. The Menu calls `arrange` and
      # `bounds` every time a button is added, so a layout whose places depend on
      # how many buttons there are — UI::Ring — re-spaces them all. It holds no
      # state about any one menu, so one instance may serve several.
      #
      # ## One arithmetic for rows of slots
      #
      # A stack places its buttons in rows of equal slots, filled left to right
      # and top to bottom. A vertical stack's rows hold one slot each, and a
      # horizontal stack's one row holds them all. UI::Grid is a stack whose rows
      # hold `columns` slots, and it overrides nothing else.
      class Stack
        AXES = %i[vertical horizontal].freeze

        attr_reader :axis, :item_width, :item_height, :spacing

        def initialize(axis:, item_width:, item_height:, spacing: 8)
          raise ArgumentError, "axis: must be one of #{AXES.inspect}, not #{axis.inspect}" unless AXES.include?(axis)

          @axis = axis
          @item_width = item_width
          @item_height = item_height
          @spacing = spacing
        end

        def arrange(buttons)
          per_row = row_length(buttons.size)
          across = @item_width + @spacing
          down = @item_height + @spacing
          buttons.each_with_index do |button, index|
            button.x = (index % per_row) * across
            button.y = (index / per_row) * down
            button.width = @item_width
            button.height = @item_height
          end
        end

        # `[x, y, width, height]` of the rows the buttons fill, relative to the
        # menu: all zero for no buttons, since no gap sits before the first. A
        # grid's single row that is not full is as wide as its buttons.
        def bounds(buttons)
          count = buttons.size
          return [0, 0, 0, 0] if count.zero?

          per_row = row_length(count)
          columns = [per_row, count].min
          rows = (count + per_row - 1) / per_row
          [0, 0, (columns * @item_width) + ((columns - 1) * @spacing), (rows * @item_height) + ((rows - 1) * @spacing)]
        end

        private

        def row_length(count) = @axis == :vertical ? 1 : count
      end
    end
  end
end
