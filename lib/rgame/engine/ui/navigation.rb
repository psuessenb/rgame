# frozen_string_literal: true

module RGame
  module Engine
    module UI
      # How a Menu turns a player's input into focus. The base of UI::Stepping
      # and UI::Pointing, and the class to subclass for a third way.
      #
      #   class Cycling < UI::Navigation
      #     def control(actions)
      #       menu.focus((menu.focused_index.to_i + 1) % menu.buttons.size) if actions.pressed?(:ui_right)
      #     end
      #   end
      #
      # A navigation only decides **which button is focused**. Confirming the
      # focused button, pressing it and firing its signal are the Menu's,
      # and the same for every navigation, so a subclass cannot forget them.
      #
      # ## One per menu
      #
      # A navigation may keep state about the menu it drives — UI::Pointing keeps
      # the last direction read — so it belongs to exactly one. Handing the same
      # instance to a second Menu raises, rather than leaving two menus quietly
      # sharing one pointer. Build a fresh one for each menu; the constructor
      # default already does.
      class Navigation
        attr_reader :menu

        # Called by Menu when it is built with this navigation.
        def attach(menu)
          if @menu && !@menu.equal?(menu)
            raise ArgumentError, "this #{self.class} already navigates another menu — build one per menu"
          end

          @menu = menu
        end

        # Reads this frame's actions and moves focus with `menu.focus`. Called
        # before the Menu handles `ui_confirm`, so a focus change and a confirm on
        # the same frame activate the newly focused button.
        def control(actions); end

        # Called after a button is added, for a navigation that has an opinion
        # about where focus starts.
        def buttons_changed; end

        # Called by Menu on each update while the menu is not paused, for a
        # navigation that counts time. Time enters here and nowhere else.
        def update(dt); end

        # Called by Menu when it opens, for a navigation holding state that
        # belongs to one opening — UI::Pointing forgets its aim.
        def opened; end
      end
    end
  end
end
