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
      # ## A menu with no navigation
      #
      # `navigation: nil` says input never moves focus: the menu focuses nothing
      # when a button is added, so `ui_confirm` has nothing to act on. What
      # focuses a button then is the game calling `focus` — which confirm then
      # acts on, as it would for any navigation.
      #
      # ## A menu acts only on a press it saw start
      #
      # A menu takes no press until it has seen `ui_confirm` up, and no hotkey
      # press on a button until it has seen that hotkey up since the button was
      # added. A menu opened from `on_activated` — a submenu — is controlled
      # later in the same tick, while the key that opened it is still down, and
      # would otherwise read the same press edge again and activate its own
      # button with it.
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
        ClosedSignal = Signal.define(:button)

        signal :on_opened
        # Emits the button a trigger's release activated, or nil.
        signal :on_closed, ClosedSignal

        # `trigger` is an action name, or nil. `scope` is a String, or nil.
        attr_reader :buttons, :focused_index, :layout, :navigation, :trigger, :scope

        # The rectangle the layout says encloses every button, relative to the
        # menu — what a subclass draws its backdrop round. Copied on each `add`,
        # so reading them on a draw path costs nothing.
        attr_reader :bounds_x, :bounds_y, :bounds_width, :bounds_height

        def initialize(layout:, navigation: Stepping.new, trigger: nil, scope: nil, **)
          super(**)
          @scope = scope&.to_s&.freeze
          @layout = layout
          @navigation = navigation
          @trigger = trigger
          @open = trigger.nil?
          @buttons = []
          @bounds_x = @bounds_y = @bounds_width = @bounds_height = 0
          @focused_index = nil
          @confirm_seen_up = false
          @trigger_seen_up = false
          @hotkey_seen_up = []
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
          @layout.arrange(@buttons)
          @bounds_x, @bounds_y, @bounds_width, @bounds_height = @layout.bounds(@buttons)
          @navigation&.on_buttons_changed
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

        def open? = @open

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

        # A trigger's press first, so an opening's first frame already reads the
        # stick; then navigation, so a focus change and a confirm on the same
        # frame confirm the newly focused button; then every hotkey; then
        # confirm, on a menu with no trigger; and a trigger's release last, so it
        # chooses what this frame focused.
        def on_control(actions)
          trigger_edge = control_trigger(actions) if @trigger
          open_now if trigger_edge == :press
          return unless @open

          @navigation&.on_control(actions)
          press_hotkeys(actions)
          @trigger ? release_trigger(trigger_edge) : confirm(actions)
        end

        # Lets the navigation count time, then does what every node does.
        def update(dt)
          @navigation&.update(dt) unless @paused
          super
        end

        private

        def open_now
          @open = true
          @navigation&.on_opened
          on_opened_signal.emit
        end

        def close_with(button)
          @open = false
          on_closed_signal.emit(button)
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

        def confirm(actions)
          edge = press_edge(actions, :ui_confirm, @confirm_seen_up)
          @confirm_seen_up = !actions.held?(:ui_confirm)
          button = focused
          pass_edge(button, edge, :confirm) if button
        end

        def press_hotkeys(actions)
          index = 0
          while index < @buttons.size
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
