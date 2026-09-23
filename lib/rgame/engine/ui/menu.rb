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
      # | `layout:` | where each button goes, its size, and the bounds of them all | UI::Column, UI::Row, UI::Ring |
      # | `navigation:` | which button this frame's input focuses | UI::Stepping (default), UI::Pointing, or nil |
      #
      # What stays here is what every menu does the same way: holding the
      # buttons, passing `ui_confirm` to the focused one as a press and a
      # release — when that activates is the button's `activate_on:` — and
      # passing each button's `hotkey` to that button, focused or not. A
      # navigation cannot forget to do either, because it is never asked to.
      #
      # `confirm:` names the action that confirms, `ui_confirm` by default.
      # `confirm: nil` builds a menu that nothing confirms, whose buttons only
      # their hotkeys press — a UI::Tabs bar, whose focused button is the page
      # shown rather than a choice waiting to be made.
      #
      # ## A menu with no navigation
      #
      # `navigation: nil` says input never moves focus: the menu focuses nothing
      # when a button is added, so `ui_confirm` has nothing to act on. What
      # focuses a button then is the game calling `focus` — which confirm then
      # acts on, as it would for any navigation.
      #
      # ## A menu acts only on a press it saw start
      #
      # A menu takes no press until it has seen its confirm action up, and no hotkey
      # press on a button until it has seen that hotkey up since the button was
      # added. A menu opened from `on_activated` — a submenu — is controlled
      # later in the same tick, while the key that opened it is still down, and
      # would otherwise read the same press edge again and activate its own
      # button with it.
      #
      # A change to the buttons starts that wait again: after `add` or `clear`,
      # the menu takes no confirm press until it has seen confirm up. A parent
      # that adds buttons on a confirm press — a dialogue box showing its
      # responses as a line ends — does so before the menu reads the same
      # press, since `control` runs a parent before its children. And a menu
      # whose buttons change from a button's `on_activated` reads no more input
      # that tick, so a new button is not pressed by the press that made it.
      #
      #   wheel = UI::Menu.new(x: 320, y: 240, navigation: UI::Pointing.new,
      #                        layout: UI::Ring.new(radius: 120, item_width: 96, item_height: 30))
      #
      # ## A scope for its buttons' keys
      #
      # `scope:` puts a scope in front of every label given as a key, so the
      # buttons of a title menu say `label: 'play'` and draw `title_menu.play`:
      #
      #   menu = UI::Menu.new(layout: column, scope: 'title_menu')
      #   menu.add(UI::PanelButton.new(label: 'play'))                                   # title_menu.play
      #   menu.add(UI::PanelButton.new(label: Engine::Text.new('quit', scope: 'common')))  # common.quit
      #
      # The menu sets it as each button is added, on a button whose
      # `label_scope` is still nil. A label given as an Engine::Text keeps its own
      # scope, nil included, and so does a literal. The scope reaches the
      # buttons of this menu and nothing deeper in the tree.
      #
      # ## Open and closed
      #
      # A closed menu draws nothing — neither its own backdrop nor its buttons —
      # and its input moves no focus and presses nothing. A menu starts open;
      # `close` and `open` are what a pause menu toggles. Closing is not
      # pausing: a closed menu still ticks, so a button's pressed feedback runs
      # out while it is shut instead of waiting to be seen again.
      #
      # ## A menu held open by an action
      #
      # `trigger:` names an action that opens the menu while it is held. Letting
      # it go activates the button focused at that moment, if any, and closes —
      # the console quick wheel, held open by a shoulder button:
      #
      #   wheel = UI::RadialMenu.new(x: 320, y: 240, radius: 150, button_width: 64, trigger: :quick_menu)
      #
      # A menu with a trigger starts closed, and `ui_confirm` activates nothing
      # on it: letting go is the only way to choose. Opening only happens on a
      # press this menu saw start, like every other press, so a trigger already
      # down when the menu appears opens nothing; and a trigger that comes up
      # while the menu is paused closes it without choosing. `open` raises on
      # such a menu, because a menu opened by hand would wait for the release of
      # a press it never saw; `close` does not, and is how a game cancels a held
      # wheel.
      #
      # What the world does while the menu is open is the game's to decide, from
      # `on_opened` and `on_closed`. The menu only says when.
      #
      # ## Focus is per player, and that costs nothing
      #
      # A Menu inside a PlayerLayer inherits that player as its `input_owner`,
      # so the `actions` its `_control` receives are already that player's.
      # Two players with a menu open at once are independent without either menu
      # knowing the other exists, and without a word of focus-specific
      # per-player machinery. That falls out of ownership being inherited down
      # the tree — see docs/api/scene_graph.md, "Who a node answers to".
      #
      # ## Several menus on one screen
      #
      # A menu joins the nearest UI::FocusGroup above it as it enters the tree,
      # and leaves as it exits. The search stops at a UI::Tabs, so a menu on a
      # page joins a group on that page or none. Only the group's current menu
      # reads input; the others draw with nothing focused. A menu outside any
      # group is always current. `focus` with an index makes a menu current, so a game that
      # focuses a button in another menu moves the player there.
      #
      # ## A window of rows
      #
      # Over a layout built with `visible_rows:`, the menu draws that many rows
      # and scrolls the rest into view. Every change of focus scrolls the
      # focused button into view by the fewest rows, whether navigation, the
      # game's `focus` or a group crossing made it, and `clear` scrolls to the
      # top. `rows_above` and `rows_below` count the rows out of view, which is
      # what a game draws a scroll arrow from. The menu's bounds are the whole
      # window's, so a UI::PanelMenu's panel keeps its size as items come and go.
      #
      # ## What this is not
      #
      # It is a menu, not a widget library. Every button is the same size, placed
      # by its layout, and that is the whole of its layout story — see
      # docs/api/ui.md, "What this is not".
      class Menu < Node2D
        signal :opened
        # Emits the button a trigger's release activated, or nil.
        signal :closed, :button

        # `trigger` is an action name, or nil. `scope` is a String, or nil.
        # `group` is the UI::FocusGroup the menu joined, or nil.
        attr_reader :buttons, :focused_index, :layout, :navigation, :trigger, :scope, :group

        # The rectangle the layout says encloses every button, relative to the
        # menu — what a subclass draws its backdrop round. Copied on each `add`,
        # so reading them on a draw path costs nothing.
        attr_reader :bounds_x, :bounds_y, :bounds_width, :bounds_height

        # The top row in view: 0 at the top, and always 0 over a layout without
        # `visible_rows`.
        attr_reader :first_row

        # `confirm` is an action name, or nil for a menu nothing confirms.
        def initialize(layout:, navigation: Stepping.new, trigger: nil, scope: nil, confirm: :ui_confirm, **)
          super(**)
          unless confirm.nil? || confirm.is_a?(Symbol)
            raise ArgumentError, "confirm: must be an action name or nil, not #{confirm.inspect}"
          end

          @confirm = confirm
          @scope = scope&.to_s&.freeze
          @layout = layout
          @visible_rows = layout.respond_to?(:visible_rows) ? layout.visible_rows : nil
          @per_row = layout.respond_to?(:columns) ? layout.columns : 1
          @first_row = 0
          @navigation = navigation
          @trigger = trigger
          @open = trigger.nil?
          @buttons = []
          @bounds_x = @bounds_y = @bounds_width = @bounds_height = 0
          @focused_index = nil
          @confirm_seen_up = false
          @trigger_seen_up = false
          @hotkey_seen_up = []
          @buttons_changed = false
          @group = nil
          navigation&.attach(self)
        end

        # Adds a button, gives it the menu's `scope` unless it has a
        # `label_scope` already, re-arranges them all, and returns it, so a
        # caller can connect to its signal in the same line. Raises TypeError for
        # anything that is not a UI::Button.
        def add(button)
          raise TypeError, "a Menu holds UI::Button instances, not #{button.class}" unless button.is_a?(Button)

          button.label_scope = @scope if @scope && button.label_scope.nil?
          @buttons << button
          @hotkey_seen_up << false
          add_node(button)
          buttons_changed
          button
        end

        # Removes every button from the menu and from the tree, focuses
        # nothing, and returns the menu, ready for `add`. A closed menu may be
        # cleared.
        def clear
          focus(nil)
          @buttons.each { remove_node(it) }
          @buttons.clear
          @hotkey_seen_up.clear
          @first_row = 0
          buttons_changed
          self
        end

        # The focused button, or nil when nothing is — which under UI::Pointing
        # is whenever the stick is at rest.
        def focused = @focused_index && @buttons[@focused_index]

        # Focuses the button at `index`, or nothing for nil. Only the buttons
        # whose focus actually changes are told. It does not check `enabled?`:
        # which buttons may take focus is the navigation's rule, and a disabled
        # button cannot be activated whatever holds it.
        #
        # An index on a menu that is not its group's current one makes it
        # current first, as a crossing would, and then focuses that button.
        def focus(index)
          @group.current = self if index && !current?
          previous = focused
          @focused_index = index
          current = focused
          previous.focused = false if previous && !previous.equal?(current)
          current&.focused = true
          scroll_to(index / @per_row) if @visible_rows && index
        end

        # Whether the button at `index` is in the window of rows the menu draws:
        # always true over a layout without `visible_rows`.
        def in_view?(index)
          return true unless @visible_rows

          row = index / @per_row
          row >= @first_row && row < @first_row + @visible_rows
        end

        # The rows out of view above the window, and below it: 0 when every
        # row fits.
        def rows_above = @first_row
        def rows_below = @visible_rows ? [row_count - @first_row - @visible_rows, 0].max : 0

        def open? = @open

        # Whether this menu reads input: true outside a group, and in one only
        # while it is the group's `current`.
        def current? = @group.nil? || @group.current.equal?(self)

        # Opens the menu, lets the navigation forget the last opening, and emits
        # `on_opened`. Nothing if already open. Raises on a menu with a trigger,
        # which only its trigger opens.
        def open
          raise "this menu is opened by holding #{@trigger.inspect}, not by #open" if @trigger
          return if @open

          open_now
        end

        # Closes the menu without activating anything and emits `on_closed` with
        # nil. Nothing if already closed.
        def close
          close_with(nil) if @open
        end

        # Draws nothing while closed.
        def draw(renderer, view)
          super if @open
        end

        # Enters the tree, then joins the nearest UI::FocusGroup above.
        def enter_tree
          return if in_tree?

          super
          join_group
        end

        # Leaves its group, then the tree.
        def exit_tree
          @group&.leave(self)
          @group = nil
          super
        end

        # Called by the menu's group when it makes the menu current. The menu
        # takes no confirm until it has seen confirm up, and its navigation
        # decides where focus starts, near `button` — the one focused in the
        # menu left, or nil.
        #
        # @api private
        def enter_from(button)
          @confirm_seen_up = false
          @navigation&.entered(button)
        end

        # A trigger's press first, so an opening's first frame already reads the
        # stick; then navigation, so a focus change and a confirm on the same
        # frame confirm the newly focused button; then every hotkey; then
        # confirm, on a menu with no trigger and a `confirm:` action; and a
        # trigger's release last, so it chooses what this frame focused.
        def _control(actions)
          trigger_edge = control_trigger(actions) if @trigger
          open_now if trigger_edge == :press
          return unless @open && reads_input?

          @buttons_changed = false
          @navigation&.control(actions)
          press_hotkeys(actions)
          return if interrupted?

          if @trigger
            release_trigger(trigger_edge)
          elsif @confirm
            confirm_focused(actions)
          end
        end

        # Lets the navigation count time, then does what every node does.
        def update(dt)
          @navigation&.update(dt) unless @paused
          super
        end

        private

        def draw_children(renderer, view)
          return super unless @visible_rows

          rgame_children_in_order.each { |child| child.draw(renderer, view) if in_window?(child) }
        end

        def in_window?(child)
          return true unless child.is_a?(Button)

          child.y >= @bounds_y && child.y + child.height <= @bounds_y + @bounds_height
        end

        def row_count = (@buttons.size + @per_row - 1) / @per_row

        def scroll_to(row)
          first = @first_row
          first = row if row < first
          first = row - @visible_rows + 1 if row >= first + @visible_rows
          return if first == @first_row

          @first_row = first
          @layout.arrange(@buttons, first)
        end

        def arrange_buttons
          if @visible_rows
            @layout.arrange(@buttons, @first_row)
          else
            @layout.arrange(@buttons)
          end
        end

        def join_group
          group = parent
          group = group.parent until group.nil? || group.is_a?(FocusGroup) || group.is_a?(Tabs)
          return unless group.is_a?(FocusGroup)

          group.join(self)
          @group = group
        end

        def reads_input? = @group.nil? || @group.reading?(self)
        def interrupted? = @buttons_changed || !current?

        def buttons_changed
          arrange_buttons
          @bounds_x, @bounds_y, @bounds_width, @bounds_height = @layout.bounds(@buttons)
          @confirm_seen_up = false
          @buttons_changed = true
          @navigation&.buttons_changed
        end

        def open_now
          @open = true
          @navigation&.opened
          opened_signal.emit
        end

        def close_with(button)
          @open = false
          closed_signal.emit(button)
        end

        def control_trigger(actions)
          edge = press_edge(actions, @trigger, @trigger_seen_up)
          @trigger_seen_up = !actions.held?(@trigger)
          edge
        end

        def release_trigger(edge)
          case edge
          when :release then close_with(focused&.activate)
          when :missed_release then close_with(nil)
          end
        end

        def confirm_focused(actions)
          edge = press_edge(actions, @confirm, @confirm_seen_up)
          @confirm_seen_up = !actions.held?(@confirm)
          button = focused
          pass_edge(button, edge, :confirm) if button
        end

        def press_hotkeys(actions)
          index = 0
          while index < @buttons.size && !interrupted?
            button = @buttons[index]
            hotkey = button.hotkey
            if hotkey
              edge = press_edge(actions, hotkey, @hotkey_seen_up[index])
              @hotkey_seen_up[index] = !actions.held?(hotkey)
              pass_edge(button, edge, :hotkey)
            end
            index += 1
          end
        end

        def press_edge(actions, action, seen_up)
          if actions.pressed?(action)
            :press if seen_up
          elsif actions.released?(action)
            :release
          elsif !actions.held?(action)
            :missed_release
          end
        end

        def pass_edge(button, edge, source)
          case edge
          when :press then button.press(source)
          when :release then button.release(source)
          when :missed_release then button.cancel_press(source)
          end
        end
      end
    end
  end
end
