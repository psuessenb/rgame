# frozen_string_literal: true

module RGame
  module Engine
    module UI
      # Focus chosen by direction: the button a stick points at is the focused
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
      # ## The button pointed at is the nearest by angle
      #
      # Each button's centre, seen from the menu's origin, is a direction, and the
      # stick's direction focuses whichever button's direction is closest. On a
      # ring centred on the origin that cuts the circle into one equal sector per
      # button, centred on it. It asks the layout nothing: the angles come from
      # where the buttons actually are, so a ring that starts somewhere else, or a
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
      # A disabled button is never focused, so pointing at one selects nothing.
      #
      # ## A grace window, for a stick that springs back
      #
      # `grace:` is how long, in seconds, focus survives the stick entering the
      # dead zone before it clears. A player choosing by letting go of a
      # trigger lets go of the stick a moment earlier, and the stick is back in
      # the middle before the trigger comes up; the window is what lets that
      # release still choose. Leaving the stick at rest for longer than it
      # chooses nothing, which is the dead-zone rule again, only later.
      #
      # It applies to the dead zone only: pointing at a disabled button clears
      # focus at once. Time is counted in `update(dt)`, so a paused menu's window
      # does not run out.
      class Pointing < Navigation
        DEAD_ZONE = 0.5
        GRACE = 0.15

        # `grace` is what was passed, or once the menu is built, the resolved
        # default. nil before then when none was passed.
        attr_reader :dead_zone, :grace, :aim_x, :aim_y

        # `grace: nil` resolves when the menu is built: 0.0, focus clearing the
        # moment the stick is at rest.
        def initialize(dead_zone: DEAD_ZONE, grace: nil)
          super()
          @dead_zone = dead_zone
          @grace = grace
          @aim_x = 0.0
          @aim_y = 0.0
          @at_rest = false
          @at_rest_for = 0.0
        end

        def attach(menu)
          super
          @grace = 0.0 if @grace.nil?
        end

        # The index of the button `(x, y)` points at, or nil if the vector is
        # shorter than the dead zone. `y` is positive downwards, like the stick
        # and the screen. Whether that button is enabled is not this method's
        # question.
        def index_at(x, y)
          return nil if Math.hypot(x, y) < @dead_zone

          aim = Math.atan2(y, x)
          nearest = nil
          best = Float::INFINITY
          menu.buttons.each_index do |index|
            gap = angle_between(aim, direction_of(menu.buttons[index]))
            next unless gap < best

            best = gap
            nearest = index
          end
          nearest
        end

        def on_control(actions)
          @aim_x = actions.axis(:ui_radial_x)
          @aim_y = actions.axis(:ui_radial_y)
          if Math.hypot(@aim_x, @aim_y) < @dead_zone
            @at_rest_for = 0.0 unless @at_rest
            @at_rest = true
            menu.focus(nil) unless @at_rest_for < @grace
          else
            @at_rest = false
            index = index_at(@aim_x, @aim_y)
            menu.focus(index && menu.buttons[index].enabled? ? index : nil)
          end
        end

        # Counts how long the stick has been at rest, for the grace window.
        def update(dt)
          @at_rest_for += dt if @at_rest
        end

        # Forgets the last aim and focuses nothing, so a menu opened again does
        # not start where the last opening left off.
        def on_opened
          @aim_x = 0.0
          @aim_y = 0.0
          @at_rest = false
          menu.focus(nil)
        end

        private

        def direction_of(button)
          Math.atan2(button.y + (button.height / 2.0), button.x + (button.width / 2.0))
        end

        def angle_between(first, second)
          gap = (first - second).abs % (Math::PI * 2)
          gap > Math::PI ? (Math::PI * 2) - gap : gap
        end
      end
    end
  end
end
