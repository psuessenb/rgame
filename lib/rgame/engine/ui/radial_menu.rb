# frozen_string_literal: true

module RGame
  module Engine
    module UI
      # Items on a ring, chosen by pointing a stick at one.
      #
      #   wheel = layer.add_node(UI::RadialMenu.new(x: 320, y: 240, radius: 120,
      #                                             item_width: 96, item_height: 30))
      #   wheel.add_item('Sword').on_activated { equip(:sword) }
      #   wheel.add_item('Bow').on_activated   { equip(:bow) }
      #
      # The node's position is the **centre** of the ring. The first item sits
      # straight up and the rest go clockwise, spaced evenly, and adding an item
      # re-spaces them all.
      #
      # ## Selection is by direction, not by position in a list
      #
      # UI::Menu moves focus *relative* to where it is: down means "the next
      # one". A stick is bad at that and good at something else — pointing — so
      # here the direction held **is** the selection. The ring is cut into one
      # sector per item, centred on it, and whichever sector `ui_radial_x` /
      # `ui_radial_y` point into is focused. `ui_confirm` activates it.
      #
      # ## Below the dead zone nothing is selected
      #
      # A stick at rest is a direction too, just a meaningless one, and a
      # released stick springs back through the middle on its way there. So a
      # deflection shorter than `dead_zone` focuses nothing, and a confirm in
      # that state activates nothing — letting go of the stick and pressing A
      # never picks whatever happened to be under it last.
      #
      # That dead zone is a *length*, measured on the combined vector. The one
      # ActionMapper applies is per axis and much smaller: it exists to stop a
      # worn stick drifting, and it would let a nearly centred stick select.
      #
      # ## Its own two axes
      #
      # It reads `ui_radial_x` and `ui_radial_y`, from the universal set every
      # InputMap is merged over, rather than `move_x` / `move_y`. They are bound
      # to the same stick by default, but as separate actions a game can move
      # the wheel to the right stick without touching how its players walk.
      #
      # ## Items are MenuItems
      #
      # What an item is — a label, four states of art, `enabled:`, an
      # `on_activated` signal — is the same whether it is chosen from a list or
      # from a ring, so it is the same class. Only how focus is decided differs,
      # and that is this class. A disabled item is never focused, so pointing at
      # one selects nothing.
      #
      # It draws nothing of its own. A backdrop or a pointer is the game's to
      # draw, and `aim_x` / `aim_y` are what the pointer would read.
      class RadialMenu < Node2D
        DEAD_ZONE = 0.5
        TAU = Math::PI * 2

        attr_reader :items, :focused_index, :radius, :dead_zone, :aim_x, :aim_y

        def initialize(radius:, item_width:, item_height:, dead_zone: DEAD_ZONE,
                       style: MenuItem::STYLE, **)
          super(**)
          @radius = radius
          @item_width = item_width
          @item_height = item_height
          @dead_zone = dead_zone
          @style = style
          @items = []
          @focused_index = nil
          @aim_x = 0.0
          @aim_y = 0.0
        end

        # Adds an item at the next place round the ring and returns it, so a
        # caller can connect to its signal in the same line.
        def add_item(label, enabled: true)
          item = MenuItem.new(label: label, enabled: enabled, style: @style,
                              width: @item_width, height: @item_height)
          @items << item
          add_node(item)
          arrange
          item
        end

        # The focused item, or nil while the stick is inside the dead zone or
        # pointing at a disabled item.
        def focused = @focused_index && @items[@focused_index]

        # The index of the sector `(x, y)` points into, or nil if the vector is
        # shorter than the dead zone. `y` is positive downwards, like the stick
        # and the screen, so `(0, -1)` is item 0.
        def sector_at(x, y)
          return nil if @items.empty? || Math.hypot(x, y) < @dead_zone

          angle = Math.atan2(x, -y)
          ((angle * @items.size / TAU) + 0.5).floor % @items.size
        end

        # Focuses the item at `index`, or nothing for nil or a disabled item.
        # Called every frame, so it allocates nothing.
        def focus(index)
          index = nil if index && !@items[index].enabled?
          @focused_index = index
          @items.each_index { |i| @items[i].focused = (i == index) }
        end

        def on_control(actions)
          @aim_x = actions.axis(:ui_radial_x)
          @aim_y = actions.axis(:ui_radial_y)
          focus(sector_at(@aim_x, @aim_y))

          current = focused
          return if current.nil?

          current.pressed = actions.held?(:ui_confirm)
          current.activate if actions.pressed?(:ui_confirm)
        end

        private

        def arrange
          count = @items.size
          @items.each_with_index do |item, index|
            angle = TAU * index / count
            item.x = (Math.sin(angle) * @radius) - (@item_width / 2.0)
            item.y = (-Math.cos(angle) * @radius) - (@item_height / 2.0)
          end
        end
      end
    end
  end
end
