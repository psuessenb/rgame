# frozen_string_literal: true

module TiledWorld
  # One player's inventory: a menu that only they can see and only they can drive.
  #
  # It lives inside their PlayerLayer, so three things are already true without
  # this class arranging any of them — it draws inside their half of the screen,
  # its coordinates are relative to that half, and the input it reads is theirs.
  # Nothing here mentions viewports, cameras or players.
  #
  # While it is open the player's walker is **paused**, so they stop moving in a
  # world that keeps running for everyone else. That is what pausing being a
  # property of a node rather than of the world is for: one node stops, the shared
  # simulation does not.
  class Inventory < Engine::Node2D
    PADDING     = 12
    ITEM_WIDTH  = 180
    ITEM_HEIGHT = 34
    SPACING     = 6
    ITEMS = ['Sea shell', 'Driftwood', 'Message in a bottle'].freeze

    def initialize(walker:, **)
      super(**)
      @walker = walker
    end

    def _enter_tree
      column = UI::Column.new(item_width: ITEM_WIDTH, item_height: ITEM_HEIGHT, spacing: SPACING)
      @menu = add_node(UI::PanelMenu.new(x: PADDING, y: PADDING, padding: PADDING, layout: column))
      ITEMS.each { |label| @menu.add(UI::PanelButton.new(label: label)).on_activated { toggle } }
      @menu.close
    end

    # A closed menu neither draws nor takes input, but this node still reads the
    # key that opens it.
    def _control(actions)
      toggle if actions.pressed?(:ui_cancel)
    end

    private

    def toggle
      @menu.open? ? @menu.close : @menu.open
      @walker.paused = @menu.open?
    end
  end
end
