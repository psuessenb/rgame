# frozen_string_literal: true

module RGame
  module Engine
    module UI
      # Focus chosen by direction: the item a stick points at is the focused
      # one. Built for a UI::Ring, which is what makes a radial menu.
      #
      #   wheel = UI::Menu.new(x: 320, y: 240,
      #                        layout: UI::Ring.new(radius: 120, item_width: 96, item_height: 30),
      #                        navigation: UI::Pointing.new)
      #
      # It reads `ui_radial_x` and `ui_radial_y` from the universal set every
      # InputMap is merged over. They share the left stick with `move_x` /
      # `move_y` by default and are still separate actions, so a game can move
      # its wheel to the right stick without rebinding how its players walk.
      #
      # ## The item pointed at is the nearest by angle
      #
      # Each item's centre, seen from the menu's origin, is a direction, and the
      # stick's direction focuses whichever item's direction is closest. On a
      # ring centred on the origin that cuts the circle into one equal sector per
      # item, centred on it. It asks the layout nothing: the angles come from
      # where the items actually are, so a ring that starts somewhere else, or a
      # layout that is not a ring, cannot disagree with it.
      #
      # ## Below the dead zone nothing is focused
      #
      # A stick at rest is a direction too, just a meaningless one, and a
      # released stick springs back through the middle on its way there. So a
      # deflection shorter than `dead_zone` focuses nothing, and a confirm in
      # that state activates nothing — letting go of the stick and pressing A
      # never picks whatever happened to be under it last.
      #
      # That dead zone is a *length*, on the combined vector, and sits on top of
      # the per-axis one ActionMapper applies: that one takes 0.15 off each axis
      # and rescales, and exists to stop a worn stick drifting. It is far too
      # small to decide that a player means a direction.
      #
      # A disabled item is never focused, so pointing at one selects nothing.
      class Pointing < Navigation
        DEAD_ZONE = 0.5

        attr_reader :dead_zone, :aim_x, :aim_y

        def initialize(dead_zone: DEAD_ZONE)
          super()
          @dead_zone = dead_zone
          @aim_x = 0.0
          @aim_y = 0.0
        end

        # The index of the item `(x, y)` points at, or nil if the vector is
        # shorter than the dead zone. `y` is positive downwards, like the stick
        # and the screen. Whether that item is enabled is not this method's
        # question.
        def index_at(x, y)
          return nil if Math.hypot(x, y) < @dead_zone

          aim = Math.atan2(y, x)
          nearest = nil
          best = Float::INFINITY
          menu.items.each_index do |index|
            gap = angle_between(aim, direction_of(menu.items[index]))
            next unless gap < best

            best = gap
            nearest = index
          end
          nearest
        end

        def on_control(actions)
          @aim_x = actions.axis(:ui_radial_x)
          @aim_y = actions.axis(:ui_radial_y)
          index = index_at(@aim_x, @aim_y)
          menu.focus(index && menu.items[index].enabled? ? index : nil)
        end

        private

        def direction_of(item)
          Math.atan2(item.y + (item.height / 2.0), item.x + (item.width / 2.0))
        end

        def angle_between(first, second)
          gap = (first - second).abs % (Math::PI * 2)
          gap > Math::PI ? (Math::PI * 2) - gap : gap
        end
      end
    end
  end
end
