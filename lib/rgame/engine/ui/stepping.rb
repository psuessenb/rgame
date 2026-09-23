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
      #
      # ## Across a grid
      #
      # On a layout that answers `columns`, such as UI::Grid, the other pair
      # moves along the column instead, and nothing is adjusted. Each line — a
      # row, or a column — wraps inside itself, and a step skips the disabled
      # buttons along it. A step onto a short last row that has no button in
      # this column takes that row's last button. `step` moves along the row. A
      # grid's axis is the order it fills in, so an `axis:` other than its own
      # raises ArgumentError.
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

        # Resolves the axis against the menu's layout, and reads its `columns`
        # if it has them. Raises ArgumentError for an axis outside
        # UI::Stack::AXES, and on a grid for an axis other than the grid's.
        def attach(menu)
          super
          layout = menu.layout
          @columns = layout.respond_to?(:columns) ? layout.columns : nil
          @axis ||= layout.axis
          unless Stack::AXES.include?(@axis)
            raise ArgumentError, "axis: must be one of #{Stack::AXES.inspect}, not #{@axis.inspect}"
          end

          refuse_grid_axis(layout.axis) if @columns
          @step_back, @step_on, @other_back, @other_on = ACTIONS.fetch(@axis)
        end

        # Moves focus by `delta` along the axis, or along the focused button's
        # row on a grid, skipping anything disabled, and wrapping. Does nothing
        # at all if no button along the way can take focus.
        def step(delta)
          count = menu.buttons.size
          index = menu.focused_index || 0
          return move(0, 1, count, index, delta) unless @columns

          start = index - (index % @columns)
          length = count - start
          length = @columns if length > @columns
          move(start, 1, length, index - start, delta)
        end

        def control(actions)
          step(-1) if actions.pressed?(@step_back)
          step(1) if actions.pressed?(@step_on)
          return control_column(actions) if @columns

          current = menu.focused
          return if current.nil?

          current.adjust(-1) if actions.pressed?(@other_back)
          current.adjust(1) if actions.pressed?(@other_on)
        end

        def buttons_changed
          return menu.focus(nil) if menu.buttons.empty?
          return if menu.focused&.enabled?

          first = menu.buttons.index(&:enabled?)
          menu.focus(first || 0)
        end

        private

        def refuse_grid_axis(grid_axis)
          return if @axis == grid_axis

          raise ArgumentError, "a grid steps along its rows, so axis: must be #{grid_axis.inspect}, " \
                               "not #{@axis.inspect}"
        end

        def control_column(actions)
          step_column(-1) if actions.pressed?(@other_back)
          step_column(1) if actions.pressed?(@other_on)
        end

        def step_column(delta)
          count = menu.buttons.size
          index = menu.focused_index || 0
          rows = (count + @columns - 1) / @columns
          move(index % @columns, @columns, rows, index / @columns, delta)
        end

        def move(start, stride, length, place, delta)
          buttons = menu.buttons
          last = buttons.size - 1
          tried = 0
          while tried < length
            place = (place + delta) % length
            index = start + (place * stride)
            index = last if index > last
            if buttons[index].enabled?
              menu.focus(index)
              return
            end
            tried += 1
          end
        end
      end
    end
  end
end
