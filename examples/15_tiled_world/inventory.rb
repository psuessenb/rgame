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
    @menu = add_node(RGame::Engine::UI::Menu.new(
                       x: PADDING, y: PADDING,
                       item_width: ITEM_WIDTH, item_height: ITEM_HEIGHT, spacing: SPACING
                     ))
    ITEMS.each { |label| @menu.add_item(label).on_activated { close } }
    @menu.paused = true # closed: it neither ticks nor draws until it is opened
  end

  # Its own hook still runs while the menu below it is paused, which is how it
  # can be reopened.
  def on_control(actions)
    toggle if actions.pressed?(:ui_cancel)
  end

  def on_draw(renderer, _view)
    return unless @open

    # No z and no band: it is under a PlayerLayer, so it is in that player's
    # HUD band already, and the menu is a child node so it draws over this panel
    # by being drawn after it.
    renderer.nine_slice(:panel, abs_x, abs_y, panel_width, panel_height)
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

  def panel_width = ITEM_WIDTH + (PADDING * 2)
  def panel_height = (ITEMS.size * ITEM_HEIGHT) + ((ITEMS.size - 1) * SPACING) + (PADDING * 2)
end
