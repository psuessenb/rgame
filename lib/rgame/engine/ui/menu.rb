# frozen_string_literal: true

module RGame
  module Engine
    module UI
      # A vertical list of things to choose from, navigated by keyboard or
      # controller.
      #
      #   menu = layer.add_node(UI::Menu.new(item_width: 220, item_height: 44))
      #   menu.add_item('Resume').on_activated { close }
      #   menu.add_item('Quit').on_activated   { game.close }
      #
      # ## Focus is the whole design
      #
      # With no pointer there is no hover, so something has to own *which
      # control is focused* and how the directions move it. That is this class,
      # and everything else about a menu follows from it: an item draws
      # differently because it is focused, and `ui_confirm` activates the focused
      # one.
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
      # It is a menu, not a widget library. Items are stacked vertically at a
      # fixed size, and that is the whole of its layout. The package this
      # replaces positioned everything absolutely and hit-tested a mouse; none
      # of it is a reference, and how UI should be laid out in general is still
      # an open question — see docs/api/ui.md, "What this is not".
      class Menu < Node2D
        # Navigation wraps: a short vertical list is quicker to use when the
        # ends join, and every console menu does it.
        def initialize(item_width:, item_height:, spacing: 8,
                       style: MenuItem::STYLE, **)
          super(**)
          @item_width = item_width
          @item_height = item_height
          @spacing = spacing
          @style = style
          @items = []
          @focused_index = 0
        end

        attr_reader :items, :focused_index

        # Adds an item below the last one and returns it, so a caller can
        # connect to its signal in the same line.
        def add_item(label, enabled: true)
          item = MenuItem.new(label: label, enabled: enabled, style: @style,
                              x: 0, y: @items.size * (@item_height + @spacing),
                              width: @item_width, height: @item_height)
          @items << item
          add_node(item)
          refocus
          item
        end

        def focused = @items[@focused_index]

        # Moves focus by `delta`, skipping anything disabled, and wrapping. Does
        # nothing at all if no item can take focus.
        def focus_by(delta)
          return if @items.empty?

          index = @focused_index
          @items.size.times do
            index = (index + delta) % @items.size
            next unless @items[index].enabled?

            focus(index)
            return
          end
        end

        def focus(index)
          @focused_index = index
          @items.each_with_index { |item, i| item.focused = (i == index) }
        end

        def on_control(actions)
          focus_by(-1) if actions.pressed?(:ui_up)
          focus_by(1) if actions.pressed?(:ui_down)

          current = focused
          return if current.nil?

          current.pressed = actions.held?(:ui_confirm)
          current.activate if actions.pressed?(:ui_confirm)
        end

        private

        # Keeps focus on something usable as items arrive: the first item to be
        # added takes it, and a disabled first item hands it on.
        def refocus
          return if focused&.enabled?

          @items.each_with_index do |item, index|
            next unless item.enabled?

            return focus(index)
          end
          focus(0)
        end
      end
    end
  end
end
