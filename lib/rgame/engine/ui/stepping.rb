# frozen_string_literal: true

module RGame
  module Engine
    module UI
      # Focus that moves one button at a time: `ui_up` and `ui_down` step through
      # the buttons in the order they were added, and `ui_left` / `ui_right` go to
      # the focused row. Menu's default navigation.
      #
      #   UI::Menu.new(layout: UI::Column.new(item_width: 220, item_height: 44))
      #
      # **Focus is never empty** while the menu has a button. It starts on the
      # first enabled one, skips disabled ones as it moves, and wraps at the
      # ends: a short list is quicker to get around when its ends join, and every
      # console menu does it.
      #
      # **Horizontal belongs to the row.** Only the row knows whether it has
      # anything to change, so the focused button is asked to `adjust` and a plain
      # PanelButton answers nil. That is what makes UI::OptionButton work, and the
      # reason an option row wants this navigation rather than UI::Pointing,
      # where left and right are directions to point in.
      class Stepping < Navigation
        # Moves focus by `delta`, skipping anything disabled, and wrapping. Does
        # nothing at all if no button can take focus.
        def step(delta)
          buttons = menu.buttons
          return if buttons.empty?

          index = menu.focused_index || 0
          buttons.size.times do
            index = (index + delta) % buttons.size
            next unless buttons[index].enabled?

            menu.focus(index)
            return
          end
        end

        def on_control(actions)
          step(-1) if actions.pressed?(:ui_up)
          step(1) if actions.pressed?(:ui_down)

          current = menu.focused
          return if current.nil?

          current.adjust(-1) if actions.pressed?(:ui_left)
          current.adjust(1) if actions.pressed?(:ui_right)
        end

        def on_buttons_changed
          return if menu.focused&.enabled?

          first = menu.buttons.index(&:enabled?)
          menu.focus(first || 0)
        end
      end
    end
  end
end
