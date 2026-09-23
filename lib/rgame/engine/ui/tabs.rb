# frozen_string_literal: true

module RGame
  module Engine
    module UI
      # Pages of one screen, and a bar of tabs that shows one of them at a time.
      #
      #   row   = UI::Row.new(item_width: 96, item_height: 28)
      #   tabs  = layer.add_node(UI::Tabs.new(x: 16, y: 8, layout: row, scope: 'inventory'))
      #   items = tabs.add(UI::PanelButton.new(label: 'items'), UI::FocusGroup.new)
      #   keys  = tabs.add(UI::PanelButton.new(label: 'key_items'), UI::FocusGroup.new)
      #
      # `ui_tab_prev` and `ui_tab_next` show the previous and the next enabled
      # tab, wrapping, and `on_changed` emits the page shown. A tab's `hotkey`
      # shows its page too, and `current=` does what a press does.
      #
      # ## The bar is a menu
      #
      # The bar is a UI::Menu over `layout:`, built with `confirm: nil` and a
      # UI::Stepping on the two tab actions. Its focused button is the tab shown,
      # so a tab draws its focused look, and `ui_confirm` never reaches it. The
      # bar is the tabs' own, so no `add`, `clear` or `close` from outside can
      # leave a tab without its page. `scope:` scopes its buttons' labels.
      #
      # ## A page is any node
      #
      # `add(button, page)` puts the button in the bar and the page under the
      # bar's bounds, so a page's own `y` of 0 starts under the tabs. Each page
      # sits in a node the tabs hold it in, which is its `parent`. The tabs
      # control and draw the page shown, and update every page. A page keeps its
      # state while hidden, so a menu on it keeps its focus. Hiding is not
      # pausing: a button's pressed look runs out while its page is hidden.
      #
      # A page shown is first controlled on the next tick, so E and confirm on
      # one frame switch the page and activate nothing on it.
      #
      # ## Tabs bound focus groups
      #
      # The bar joins no UI::FocusGroup, and a menu on a page joins a group on
      # that page or none, because the search for a group stops at the tabs. So
      # a crossing never lands on the bar or on a hidden page. A `Tabs` inside
      # another's page raises ArgumentError as it enters the tree, since one
      # press would switch both.
      #
      # ## Open and closed
      #
      # A closed `Tabs` draws nothing, and nothing under it reads input. It still
      # ticks, as a closed UI::Menu does. A `Tabs` starts open, and a screen that
      # opens is a `Tabs` that opens.
      class Tabs < Node2D
        ACTIONS = %i[ui_tab_prev ui_tab_next].freeze

        # Emits the page shown, each time it changes: a tab stepped to, a
        # hotkey, `current=`, or the first tab added.
        signal :changed, :page
        signal :opened
        signal :closed

        # `pages` holds every page, in the order their tabs were added.
        # `current` is the page shown, or nil before the first tab.
        attr_reader :pages, :current

        # `layout` places the tabs; `scope` scopes their labels' keys.
        def initialize(layout:, scope: nil, **)
          super(**)
          @pages = []
          @sheets = []
          @current = nil
          @shown = nil
          @open = true
          @passes = 0
          @shown_on = 0
          @bar = add_node(Bar.new(self, layout: layout, scope: scope, confirm: nil,
                                        navigation: Stepping.new(actions: ACTIONS)))
        end

        # Puts `button` in the bar and `page` under it, and returns the page.
        # Raises TypeError for a page that is not a Node2D, and ArgumentError
        # for one the tabs already hold.
        def add(button, page)
          raise TypeError, "a page is a Node2D, not #{page.class}" unless page.is_a?(Node2D)
          raise ArgumentError, "#{page.inspect} is already a page of these tabs" if @pages.include?(page)

          sheet = add_node(Sheet.new(self))
          sheet.add_node(page)
          @pages << page
          @sheets << sheet
          @bar.add(button).on_activated { self.current = page }
          place_sheets
          page
        end

        # Shows `page`, as a press of its tab would. Emits `on_changed` only
        # when the page shown changes. Raises ArgumentError for a page the tabs
        # do not hold.
        def current=(page)
          index = @pages.index(page)
          raise ArgumentError, "#{page.inspect} is not a page of these tabs" if index.nil?

          @bar.focus(index)
        end

        def open? = @open

        # Opens the tabs and emits `on_opened`. Nothing if already open.
        def open
          return if @open

          @open = true
          opened_signal.emit
        end

        # Closes the tabs and emits `on_closed`. Nothing if already closed.
        def close
          return unless @open

          @open = false
          closed_signal.emit
        end

        # Counts the pass, so a page shown on it reads from the next, then does
        # what every node does. Nothing while closed.
        def control(input)
          return unless @open

          @passes += 1 unless @paused
          super
        end

        # Draws nothing while closed.
        def draw(renderer, view)
          super if @open
        end

        # Refuses to enter the tree inside another `Tabs`, then enters it.
        def enter_tree
          return if in_tree?

          refuse_nesting
          super
        end

        # Called by the bar when its focus moves: shows the page of the focused
        # tab.
        #
        # @api private
        def tab_focused
          index = @bar.focused_index
          sheet = index && @sheets[index]
          return if sheet.nil? || sheet.equal?(@shown)

          @shown = sheet
          @current = @pages[index]
          @shown_on = @passes
          changed_signal.emit(@current)
        end

        # Whether `sheet` holds the page shown.
        #
        # @api private
        def shows?(sheet) = sheet.equal?(@shown)

        # Whether `sheet` holds the page shown, and already did when this pass
        # began.
        #
        # @api private
        def reading?(sheet) = sheet.equal?(@shown) && @shown_on < @passes

        private

        def place_sheets
          top = @bar.bounds_y + @bar.bounds_height
          @sheets.each { it.y = top }
        end

        def refuse_nesting
          node = parent
          until node.nil?
            if node.is_a?(Tabs)
              raise ArgumentError, 'a Tabs inside another\'s page would switch with it on every press; ' \
                                   'put the two side by side'
            end

            node = node.parent
          end
        end

        # The bar: a Menu that tells its tabs each time its focus moves.
        class Bar < Menu
          def initialize(tabs, **)
            @tabs = tabs
            super(**)
          end

          # Focuses as every menu does, then shows the focused tab's page.
          def focus(index)
            super
            @tabs.tab_focused
          end
        end

        # What a page sits in: controlled only while its page is shown and
        # was already shown when the pass began, and drawn only while shown.
        class Sheet < Node2D
          def initialize(tabs)
            super()
            @tabs = tabs
          end

          def control(input)
            super if @tabs.reading?(self)
          end

          def draw(renderer, view)
            super if @tabs.shows?(self)
          end
        end

        private_constant :Bar, :Sheet
      end
    end
  end
end
