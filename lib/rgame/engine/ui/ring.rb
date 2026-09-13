# frozen_string_literal: true

module RGame
  module Engine
    module UI
      # A Menu layout: items spaced evenly round a circle **centred on the
      # menu's origin**, the first straight up and the rest clockwise.
      #
      #   UI::Menu.new(x: 320, y: 240, navigation: UI::Pointing.new,
      #                layout: UI::Ring.new(radius: 120, item_width: 96, item_height: 30))
      #
      # Each item is centred on its point of the circle, so `radius` is the
      # distance from the menu's origin to an item's middle. Adding an item
      # re-spaces every item, because the gap between them depends on how many
      # there are.
      #
      # Paired with UI::Pointing it is a radial menu. With the default
      # UI::Stepping it is a ring that `ui_up` and `ui_down` step round, which is
      # why its `axis` is `:vertical`.
      class Ring
        attr_reader :radius, :item_width, :item_height

        def axis = :vertical

        def initialize(radius:, item_width:, item_height:)
          @radius = radius
          @item_width = item_width
          @item_height = item_height
        end

        def arrange(items)
          count = items.size
          items.each_with_index do |item, index|
            angle = Math::PI * 2 * index / count
            item.x = (Math.sin(angle) * @radius) - (@item_width / 2.0)
            item.y = (-Math.cos(angle) * @radius) - (@item_height / 2.0)
            item.width = @item_width
            item.height = @item_height
          end
        end

        # `[x, y, width, height]` of the square that encloses the whole circle
        # of slots, centred on the menu's origin — not the tightest box round
        # the items placed so far, so a backdrop keeps its size as a ring grows.
        # All zero for no items.
        def bounds(items)
          return [0, 0, 0, 0] if items.empty?

          [-@radius - (@item_width / 2.0), -@radius - (@item_height / 2.0),
           (@radius * 2) + @item_width, (@radius * 2) + @item_height]
        end
      end
    end
  end
end
