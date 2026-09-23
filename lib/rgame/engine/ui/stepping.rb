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
      #
      # ## In a focus group
      #
      # A step that reaches the end of its line asks the menu's UI::FocusGroup
      # to `cross` that way, and wraps only when the group answers false. The
      # end is where no enabled button is left before the edge. A direction the
      # focused button is not `adjustable?` in crosses too, so left and right
      # leave a column of plain buttons, and still adjust an OptionButton at the
      # end of its values. A menu the group enters focuses the enabled button
      # nearest the one focus left, among those in view on a menu that scrolls.
      #
      # **Focus is never empty** holds for the group's current menu. The others
      # focus nothing, and a button added to one focuses nothing there.
      #
      # ## Two actions of its own
      #
      # `actions:` names the two actions that step back and on, in place of the
      # axis's pair. Such a navigation reads nothing else, adjusts nothing and
      # never crosses, and wraps at both ends. A UI::Tabs bar steps this way, on
      # `ui_tab_prev` and `ui_tab_next`, so the arrow keys stay with the page:
      #
      #   UI::Menu.new(layout: row, confirm: nil, navigation: UI::Stepping.new(actions: %i[ui_tab_prev ui_tab_next]))
      class Stepping < Navigation
        ACTIONS = {
          vertical: %i[ui_up ui_down ui_left ui_right].freeze,
          horizontal: %i[ui_left ui_right ui_up ui_down].freeze
        }.freeze

        DIRECTIONS = { ui_up: :up, ui_down: :down, ui_left: :left, ui_right: :right }.freeze

        # The axis focus moves along: what was passed, or once the menu is
        # built, its layout's. nil before then when none was passed.
        attr_reader :axis

        # The two action names that step back and on, or nil when the axis
        # decides.
        attr_reader :actions

        # Raises ArgumentError when `actions` is neither nil nor two Symbols.
        def initialize(axis: nil, actions: nil)
          super()
          unless actions.nil? || (actions.is_a?(Array) && actions.size == 2 && actions.all?(Symbol))
            raise ArgumentError, "actions: must be two action names, not #{actions.inspect}"
          end

          @axis = axis
          @actions = actions&.dup&.freeze
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
          @back_direction = DIRECTIONS.fetch(@step_back)
          @on_direction = DIRECTIONS.fetch(@step_on)
          @other_back_direction = DIRECTIONS.fetch(@other_back)
          @other_on_direction = DIRECTIONS.fetch(@other_on)
          @step_back, @step_on = @actions if @actions
        end

        # Moves focus by `delta` along the axis, or along the focused button's
        # row on a grid, skipping anything disabled. At the end of the line it
        # crosses to the menu's group's neighbour that way, if there is one, and
        # wraps otherwise. Does nothing at all if no button along the way can
        # take focus.
        def step(delta)
          count = menu.buttons.size
          index = menu.focused_index || 0
          direction = delta.negative? ? @back_direction : @on_direction
          return move(0, 1, count, index, delta, direction) unless @columns

          start = index - (index % @columns)
          length = count - start
          length = @columns if length > @columns
          move(start, 1, length, index - start, delta, direction)
        end

        def control(actions)
          step(-1) if actions.pressed?(@step_back)
          step(1) if actions.pressed?(@step_on) && menu.current?
          return if @actions

          other(-1) if actions.pressed?(@other_back) && menu.current?
          other(1) if actions.pressed?(@other_on) && menu.current?
        end

        def buttons_changed
          return menu.focus(nil) if menu.buttons.empty?

          focus_first if menu.current?
        end

        # Focuses the enabled button nearest `from`, among those in view on a
        # menu that scrolls, or with no `from`, keeps an enabled focus or takes
        # the first enabled button.
        def entered(from)
          return if menu.buttons.empty?
          return focus_first if from.nil?

          menu.focus(nearest_enabled(from, in_view: true) || nearest_enabled(from, in_view: false) || 0)
        end

        private

        def refuse_grid_axis(grid_axis)
          return if @axis == grid_axis

          raise ArgumentError, "a grid steps along its rows, so axis: must be #{grid_axis.inspect}, " \
                               "not #{@axis.inspect}"
        end

        def focus_first
          return if menu.focused&.enabled?

          menu.focus(menu.buttons.index(&:enabled?) || 0)
        end

        def other(delta)
          return step_column(delta) if @columns

          button = menu.focused
          return if button.nil?
          return button.adjust(delta) if button.adjustable?

          menu.group&.cross(delta.negative? ? @other_back_direction : @other_on_direction)
        end

        def step_column(delta)
          count = menu.buttons.size
          index = menu.focused_index || 0
          rows = (count + @columns - 1) / @columns
          direction = delta.negative? ? @other_back_direction : @other_on_direction
          move(index % @columns, @columns, rows, index / @columns, delta, direction)
        end

        def move(start, stride, length, place, delta, direction)
          buttons = menu.buttons
          last = buttons.size - 1
          asked = false
          tried = 0
          while tried < length
            place += delta
            if !asked && (place.negative? || place >= length)
              return if @actions.nil? && menu.group&.cross(direction)

              asked = true
            end
            index = start + ((place % length) * stride)
            index = last if index > last
            if buttons[index].enabled?
              menu.focus(index)
              return
            end
            tried += 1
          end
        end

        def nearest_enabled(from, in_view:)
          x = from.world_x + (from.width / 2.0)
          y = from.world_y + (from.height / 2.0)
          buttons = menu.buttons
          nearest = nil
          shortest = Float::INFINITY
          index = 0
          while index < buttons.size
            button = buttons[index]
            if button.enabled? && (!in_view || menu.in_view?(index))
              across = button.world_x + (button.width / 2.0) - x
              down = button.world_y + (button.height / 2.0) - y
              distance = (across * across) + (down * down)
              if distance < shortest
                nearest = index
                shortest = distance
              end
            end
            index += 1
          end
          nearest
        end
      end
    end
  end
end
