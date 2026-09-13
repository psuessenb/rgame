# frozen_string_literal: true

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
class Inventory < RGame::Engine::Node2D
  PADDING     = 12
  ITEM_WIDTH  = 180
  ITEM_HEIGHT = 34
  SPACING     = 6
  ITEMS = ['Sea shell', 'Driftwood', 'Message in a bottle'].freeze

  def initialize(walker:, **)
    super(**)
    @walker = walker
    @open = false
  end

  def on_add
    column = RGame::Engine::UI::Column.new(item_width: ITEM_WIDTH, item_height: ITEM_HEIGHT, spacing: SPACING)
    @menu = add_node(RGame::Engine::UI::PanelMenu.new(x: PADDING, y: PADDING, padding: PADDING, layout: column))
    ITEMS.each { |label| @menu.add(RGame::Engine::UI::PanelButton.new(label: label)).on_activated { close } }
    @menu.paused = true
  end

  # Its own hook still runs while the menu below it is paused, which is how it
  # can be reopened.
  def on_control(actions)
    toggle if actions.pressed?(:ui_cancel)
  end

  # The menu is a child, so skipping the child pass is what closes it visually.
  # Pausing alone would stop it ticking and leave it on screen.
  def draw_children(renderer, view)
    super if @open
  end

  private

  if @open
    def close
      toggle
    end
  end

  def toggle
    @open = !@open
    @menu.paused = !@open
    @walker.paused = @open
  end
end
