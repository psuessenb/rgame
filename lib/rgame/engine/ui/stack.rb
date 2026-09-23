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
      # hold `columns` slots, and it overrides the length of a row and nothing
      # else.
      #
      # ## A window of rows
      #
      # A stack built with `visible_rows:` shows that many rows at a time, and
      # the Menu scrolls them. Such a layout answers `visible_rows`, and takes
      # `arrange(buttons, first_row)`, which places the row `first_row` at the
      # menu's origin. Its `bounds` are the whole window's, however many rows are
      # filled. UI::Column and UI::Grid take it; a UI::Row has one row.
      class Stack
        AXES = %i[vertical horizontal].freeze

        # `visible_rows` is the number of rows in view, or nil for all of them.
        attr_reader :axis, :item_width, :item_height, :spacing, :visible_rows

        # Raises ArgumentError for an axis outside AXES, and for a
        # `visible_rows` that is neither nil nor a positive Integer.
        def initialize(axis:, item_width:, item_height:, spacing: 8, visible_rows: nil)
          raise ArgumentError, "axis: must be one of #{AXES.inspect}, not #{axis.inspect}" unless AXES.include?(axis)
          unless visible_rows.nil? || (visible_rows.is_a?(Integer) && visible_rows.positive?)
            raise ArgumentError, "visible_rows: must be a positive Integer or nil, not #{visible_rows.inspect}"
          end

          @axis = axis
          if visible_rows && one_row?
            raise ArgumentError, 'a horizontal Stack has one row, so visible_rows: has nothing to scroll'
          end

          @item_width = item_width
          @item_height = item_height
          @spacing = spacing
          @visible_rows = visible_rows
        end

        # Places each button, with the row `first_row` at the menu's origin; the
        # rows before it sit above the origin and those after below.
        def arrange(buttons, first_row = 0)
          per_row = row_length(buttons.size)
          across = @item_width + @spacing
          down = @item_height + @spacing
          index = 0
          while index < buttons.size
            button = buttons[index]
            button.x = (index % per_row) * across
            button.y = ((index / per_row) - first_row) * down
            button.width = @item_width
            button.height = @item_height
            index += 1
          end
        end

        # `[x, y, width, height]` of the rows the buttons fill, relative to the
        # menu: all zero for no buttons, since no gap sits before the first. A
        # grid's single row that is not full is as wide as its buttons. With
        # `visible_rows`, the window's, whatever the buttons fill.
        def bounds(buttons)
          count = buttons.size
          return window if @visible_rows
          return [0, 0, 0, 0] if count.zero?

          per_row = row_length(count)
          columns = [per_row, count].min
          rows = (count + per_row - 1) / per_row
          [0, 0, span(columns, @item_width), span(rows, @item_height)]
        end

        private

        def row_length(count) = @axis == :vertical ? 1 : count
        def one_row? = @axis == :horizontal
        def span(slots, size) = (slots * size) + ((slots - 1) * @spacing)
        def window = [0, 0, span(row_length(1), @item_width), span(@visible_rows, @item_height)]
      end
    end
  end
end
