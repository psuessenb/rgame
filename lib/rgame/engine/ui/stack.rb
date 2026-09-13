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
          vertical = @axis == :vertical
          step = (vertical ? @item_height : @item_width) + @spacing
          buttons.each_with_index do |button, index|
            button.x = vertical ? 0 : index * step
            button.y = vertical ? index * step : 0
            button.width = @item_width
            button.height = @item_height
          end
        end

        # `[x, y, width, height]` of the buttons in their line, relative to the
        # menu: all zero for no buttons, since no gap sits before the first.
        def bounds(buttons)
          count = buttons.size
          return [0, 0, 0, 0] if count.zero?

          if @axis == :vertical
            [0, 0, @item_width, (count * @item_height) + ((count - 1) * @spacing)]
          else
            [0, 0, (count * @item_width) + ((count - 1) * @spacing), @item_height]
          end
        end
      end
    end
  end
end
