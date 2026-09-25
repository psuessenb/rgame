# frozen_string_literal: true

module RGame
  module Engine
    module UI
      # A menu that draws its own backdrop: a nine-slice round its buttons,
      # grown by `padding` on every side.
      #
      #   column = UI::Column.new(item_width: 180, item_height: 34)
      #   menu = layer.add_node(UI::PanelMenu.new(x: 56, y: 56, layout: column))
      #   menu.add(UI::PanelButton.new(label: 'Resume')).on_activated { close }
      #
      # The panel is sized from the menu's bounds, which the layout recomputes on
      # every `add`, so a button added later grows the panel with it — there is
      # no count to keep in step with the buttons. The menu's origin stays the
      # layout's origin: with a UI::Column that is the first button's corner, and
      # the panel reaches `padding` beyond it up and to the left.
      #
      # The buttons are children, so they draw over the panel without a `z`.
      class PanelMenu < Menu
        sealed_reader :panel, :padding

        def initialize(panel: :panel, padding: 16, **)
          super(**)
          @rgame_panel = panel
          @rgame_padding = padding
        end

        def _draw(renderer, _view)
          renderer.nine_slice(@rgame_panel, bounds_x - @rgame_padding, bounds_y - @rgame_padding,
                              bounds_width + (@rgame_padding * 2), bounds_height + (@rgame_padding * 2))
        end
      end
    end
  end
end
