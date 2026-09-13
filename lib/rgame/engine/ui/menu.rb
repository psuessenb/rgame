# frozen_string_literal: true

module RGame
  module Engine
    module UI
      # Things to choose from, navigated by keyboard or controller.
      #
      #   menu = layer.add_node(UI::Menu.new(layout: UI::Column.new(item_width: 220, item_height: 44)))
      #   menu.add_item('Resume').on_activated { close }
      #   menu.add_item('Quit').on_activated   { game.close }
      #
      # ## Focus is the whole design
      #
      # With no pointer there is no hover, so something has to own *which item
      # is focused*. That is this class, and everything else about a menu
      # follows from it: an item draws differently because it is focused, and
      # `ui_confirm` activates the focused one.
      #
      # ## Two questions are handed off, and one is kept
      #
      # A list and a radial wheel are the same menu. What differs is **where the
      # items sit** and **how input moves focus**, so those two are passed in:
      #
      # | | Answers | Shipped |
      # |---|---|---|
      # | `layout:` | where each item goes, and its size | UI::Column, UI::Ring |
      # | `navigation:` | which item this frame's input focuses | UI::Stepping (default), UI::Pointing |
      #
      # What stays here is what every menu does the same way: holding the items,
      # and on `ui_confirm` drawing the focused one pressed and activating it. A
      # navigation cannot forget to do that, because it is never asked to.
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
      # It is a menu, not a widget library. Every item is the same size, placed
      # by its layout, and that is the whole of its layout story — see
      # docs/api/ui.md, "What this is not".
      class Menu < Node2D
        attr_reader :items, :focused_index, :layout, :navigation

        def initialize(layout:, navigation: Stepping.new, style: MenuItem::STYLE, **)
          super(**)
          @layout = layout
          @navigation = navigation
          @style = style
          @items = []
          @focused_index = nil
          navigation.attach(self)
        end

        # Adds an item and returns it, so a caller can connect to its signal in
        # the same line.
        def add_item(label, enabled: true)
          append(MenuItem.new(label: label, enabled: enabled, style: @style))
        end

        # Adds a row whose value is chosen from `values` with `ui_left` and
        # `ui_right` — a settings row. See UI::OptionItem, which is also where
        # `display` is explained. Those two actions reach it through
        # UI::Stepping; under UI::Pointing they are directions instead.
        def add_option(label, values:, index: 0, display: :to_s.to_proc, enabled: true)
          append(OptionItem.new(label: label, values: values, index: index, display: display,
                                enabled: enabled, style: @style))
        end

        # The focused item, or nil when nothing is — which under UI::Pointing is
        # whenever the stick is at rest.
        def focused = @focused_index && @items[@focused_index]

        # Focuses the item at `index`, or nothing for nil, and tells every item
        # whether it is the one. It does not check `enabled?`: which items may
        # take focus is the navigation's rule, and a disabled item cannot be
        # activated whatever holds it.
        def focus(index)
          @focused_index = index
          @items.each_index { |i| @items[i].focused = (i == index) }
        end

        def on_control(actions)
          @navigation.on_control(actions)

          current = focused
          return if current.nil?

          current.pressed = actions.held?(:ui_confirm)
          current.activate if actions.pressed?(:ui_confirm)
        end

        private

        def append(item)
          @items << item
          add_node(item)
          @layout.arrange(@items)
          @navigation.on_items_changed
          item
        end
      end
    end
  end
end
