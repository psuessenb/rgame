# frozen_string_literal: true

module RGame
  module Engine
    module UI
      # Focus that moves one button at a time, along an axis: on a vertical one
      # `ui_up` and `ui_down` step through the buttons in the order they were
      # added and `ui_left` / `ui_right` go to the focused button; on a
      # horizontal one the two pairs swap. Menu's default navigation.
      #
      #   UI::Menu.new(layout: UI::Column.new(item_width: 220, item_height: 44))  # up and down
      #   UI::Menu.new(layout: UI::Row.new(item_width: 64, item_height: 64))      # left and right
      #
      # **The axis is the layout's** unless one is passed, so a UI::Row steps
      # with left and right with nothing else said. `Stepping.new(axis:
      # :horizontal)` overrides it — a UI::Ring stepped round with left and
      # right, say. It is read once, when the menu is built.
      #
      # **Focus is never empty** while the menu has a button. It starts on the
      # first enabled one, skips disabled ones as it moves, and wraps at the
      # ends: a short list is quicker to get around when its ends join, and every
      # console menu does it.
      #
      # **The other pair belongs to the focused button.** Only the button knows
      # whether it has anything to change, so it is asked to `adjust` and a plain
      # PanelButton answers nil. That is what makes UI::OptionButton work, and the
      # reason an option row wants this navigation rather than UI::Pointing,
      # where every direction is one to point in.
      class Stepping < Navigation
        ACTIONS = {
          vertical: %i[ui_up ui_down ui_left ui_right].freeze,
          horizontal: %i[ui_left ui_right ui_up ui_down].freeze
        }.freeze

        # The axis focus moves along: what was passed, or once the menu is
        # built, its layout's. nil before then when none was passed.
        attr_reader :axis

        def initialize(axis: nil)
          super()
          @axis = axis
        end

        # Resolves the axis against the menu's layout. Raises ArgumentError for
        # an axis outside UI::Stack::AXES.
        def attach(menu)
          super
          @axis ||= menu.layout.axis
          unless Stack::AXES.include?(@axis)
            raise ArgumentError, "axis: must be one of #{Stack::AXES.inspect}, not #{@axis.inspect}"
          end

          @step_back, @step_on, @adjust_down, @adjust_up = ACTIONS.fetch(@axis)
        end

        # Moves focus by `delta`, skipping anything disabled, and wrapping. Does
        # nothing at all if no button can take focus.
        def step(delta)
          buttons = menu.buttons
          count = buttons.size
          index = menu.focused_index || 0
          tried = 0
          while tried < count
            index = (index + delta) % count
            if buttons[index].enabled?
              menu.focus(index)
              return
            end
            tried += 1
          end
        end

        def on_control(actions)
          step(-1) if actions.pressed?(@step_back)
          step(1) if actions.pressed?(@step_on)

          current = menu.focused
          return if current.nil?

          current.adjust(-1) if actions.pressed?(@adjust_down)
          current.adjust(1) if actions.pressed?(@adjust_up)
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
