# frozen_string_literal: true

module RGame
  module Engine
    module UI
      # A Menu layout: items stacked downwards from the menu's origin, all the
      # same size, `spacing` pixels apart.
      #
      #   UI::Menu.new(layout: UI::Column.new(item_width: 220, item_height: 44))
      #
      # A layout is anything that answers `arrange(items)` by setting each
      # item's position and size, relative to the menu, and `bounds(items)` with
      # the rectangle that encloses them. The Menu calls both every time an item
      # is added, so a layout whose places depend on how many items there are —
      # UI::Ring — re-spaces them all. It holds no state about any one menu, so
      # one instance may serve several.
      class Column
        attr_reader :item_width, :item_height, :spacing

        def initialize(item_width:, item_height:, spacing: 8)
          @item_width = item_width
          @item_height = item_height
          @spacing = spacing
        end

        def arrange(items)
          items.each_with_index do |item, index|
            item.x = 0
            item.y = index * (@item_height + @spacing)
            item.width = @item_width
            item.height = @item_height
          end
        end

        # `[x, y, width, height]` of the stacked items, relative to the menu:
        # all zero for no items, since no gap sits above the first.
        def bounds(items)
          count = items.size
          return [0, 0, 0, 0] if count.zero?

          [0, 0, @item_width, (count * @item_height) + ((count - 1) * @spacing)]
        end
      end
    end
  end
end
