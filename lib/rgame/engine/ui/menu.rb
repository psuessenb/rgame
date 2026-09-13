# frozen_string_literal: true

module RGame
  module Engine
    module UI
      # Buttons to choose from, navigated by keyboard or controller.
      #
      #   menu = layer.add_node(UI::Menu.new(layout: UI::Column.new(item_width: 220, item_height: 44)))
      #   menu.add(UI::PanelButton.new(label: 'Resume')).on_activated { close }
      #   menu.add(UI::PanelButton.new(label: 'Quit')).on_activated   { game.close }
      #
      # ## Focus is the whole design
      #
      # With no pointer there is no hover, so something has to own *which button
      # is focused*. That is this class, and everything else about a menu
      # follows from it: a button draws differently because it is focused, and
      # `ui_confirm` activates the focused one.
      #
      # ## The menu holds buttons; it does not build them
      #
      # What a button looks like is the button's business — any UI::Button
      # subclass, shipped or written by the game, goes in through `add`. The menu
      # never picks a look, so one menu can hold a panel button next to a game's
      # own.
      #
      # ## Two questions are handed off, and one is kept
      #
      # A list and a radial wheel are the same menu. What differs is **where the
      # buttons sit** and **how input moves focus**, so those two are passed in:
      #
      # | | Answers | Shipped |
      # |---|---|---|
      # | `layout:` | where each button goes, and its size | UI::Column, UI::Ring |
      # | `navigation:` | which button this frame's input focuses | UI::Stepping (default), UI::Pointing |
      #
      # What stays here is what every menu does the same way: holding the
      # buttons, and on `ui_confirm` pressing the focused one and activating it.
      # A navigation cannot forget to do that, because it is never asked to.
      #
      #   wheel = UI::Menu.new(x: 320, y: 240, navigation: UI::Pointing.new,
      #                        layout: UI::Ring.new(radius: 120, item_width: 96, item_height: 30))
      #
      # ## Focus is per player, and that costs nothing
      #
      # A Menu inside a PlayerLayer inherits that player as its `input_owner`,
      # so the `actions` its `on_control` receives are already that player's.
      # Two players with a menu open at once are independent without either menu
      # knowing the other exists, and without a word of focus-specific
      # per-player machinery. That falls out of ownership being inherited down
      # the tree — see docs/api/scene_graph.md, "Who a node answers to".
      #
      # ## What this is not
      #
      # It is a menu, not a widget library. Every button is the same size, placed
      # by its layout, and that is the whole of its layout story — see
      # docs/api/ui.md, "What this is not".
      class Menu < Node2D
        attr_reader :buttons, :focused_index, :layout, :navigation

        def initialize(layout:, navigation: Stepping.new, **)
          super(**)
          @layout = layout
          @navigation = navigation
          @buttons = []
          @focused_index = nil
          navigation.attach(self)
        end

        # Adds a button, re-arranges them all, and returns it, so a caller can
        # connect to its signal in the same line. Raises TypeError for anything
        # that is not a UI::Button.
        def add(button)
          raise TypeError, "a Menu holds UI::Button instances, not #{button.class}" unless button.is_a?(Button)

          @buttons << button
          add_node(button)
          @layout.arrange(@buttons)
          @navigation.on_buttons_changed
          button
        end

        # The focused button, or nil when nothing is — which under UI::Pointing
        # is whenever the stick is at rest.
        def focused = @focused_index && @buttons[@focused_index]

        # Focuses the button at `index`, or nothing for nil. Only the buttons
        # whose focus actually changes are told. It does not check `enabled?`:
        # which buttons may take focus is the navigation's rule, and a disabled
        # button cannot be activated whatever holds it.
        def focus(index)
          previous = focused
          @focused_index = index
          current = focused
          previous.focused = false if previous && !previous.equal?(current)
          current&.focused = true
        end

        def on_control(actions)
          @navigation.on_control(actions)

          current = focused
          return if current.nil?

          current.pressed = actions.held?(:ui_confirm)
          current.activate if actions.pressed?(:ui_confirm)
        end
      end
    end
  end
end
