# frozen_string_literal: true

# Inventory — a bag of items in a grid, and a column of verbs beside it.
#
# Run it:
#
#   ruby examples/inventory/main.rb
#
# The arrow keys (or the d-pad) move through the bag. Right from the end of a row
# crosses into the verbs, and left crosses back. Enter (or A) uses or drops the
# item chosen in the bag. It exercises:
#   - UI::Grid — a menu layout of rows of four slots, filled left to right;
#   - UI::Stepping across a grid — left and right along a row, up and down along
#     a column, each line wrapping inside itself;
#   - UI::FocusGroup — two menus on one screen, and the one of them that reads
#     input;
#   - UI::PanelMenu and UI::IconButton — the bag's slots, which draw no captions;
#   - a UI atlas's `images` — the items, cut from two strips by name.
#
# ## Focus crosses where a line ends
#
# The bag and the verbs are two menus in one UI::FocusGroup, and only the
# group's current menu reads a press. Neither menu knows the other exists. Right
# at the end of a row finds no button left in the bag, so the group crosses to
# the menu beside it. Left and right on a verb cross too, because a plain button
# has nothing to adjust. Up and down find no menu above or below, so they wrap
# inside the line, and a step onto the short last row takes its last item.
#
# Crossing clears the bag's focus, so the verbs cannot read the chosen item off
# it. The bag keeps the item last focused there, and the verbs act on that one.
# The panel under the bag names it, and is the only place an item's name is
# drawn.
#
# ## What this example does not solve
#
# The bag holds what fits in its panel: no scrolling, no pages, no stacks of one
# item. Using an item changes nothing but the status line.

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

WIDTH  = 640
HEIGHT = 480
ASSETS = File.expand_path('../assets', __dir__)
LOCALES = File.expand_path('locales', __dir__) # the text on screen: locales/en.yml

# One thing the bag holds. Its key names both its translation under `items` and
# its picture, an entry of skills.json's or icons.json's `images`.
class Item
  attr_reader :name, :image

  def initialize(key)
    @name = RGame::Engine::Text.new(key.to_s, scope: 'items')
    @image = key
  end
end

# The bag, the verbs, and the panel naming the chosen item.
class Inventory < RGame::Engine::Node2D
  UI = RGame::Engine::UI

  SLOT = 64
  ITEMS = %i[wand wrench torch hammer watering_can star trophy gear].freeze
  SLOT_STYLE = UI::ShapeStyle.new
  CLICK = 'blip.ogg'

  def initialize(**)
    super
    @carried = ITEMS.map { |key| Item.new(key) }
    @chosen = nil
    @help = RGame::Engine::Text.new('help.keys')
    @nothing = RGame::Engine::Text.new('panel.nothing')
    @ready = RGame::Engine::Text.new('status.ready')
    @used = RGame::Engine::Text.new('status.used', :item)
    @dropped = RGame::Engine::Text.new('status.dropped', :item)
    @status = @ready
    @status_item = nil
    build_menus
    fill_bag
  end

  # Keeps the item the bag last focused, which the verbs act on. Focus in the
  # verbs leaves it as it was.
  def _update(_dt)
    @chosen = @carried[@bag.focused_index] if @bag.focused
    @status.with(item: @status_item.name.to_s) if @status_item
  end

  def _draw(renderer, _view)
    renderer.text(@help, 16, 12)
    renderer.nine_slice(:panel, 16, 244, 306, 56)
    renderer.text(@chosen ? @chosen.name : @nothing, 32, 262)
    renderer.text(@status, 16, HEIGHT - 32)
  end

  private

  def build_menus
    group = add_node(UI::FocusGroup.new)
    grid = UI::Grid.new(columns: 4, item_width: SLOT, item_height: SLOT, spacing: 6)
    @bag = group.add_node(UI::PanelMenu.new(x: 32, y: 64, layout: grid))
    column = UI::Column.new(item_width: 160, item_height: 32)
    verbs = group.add_node(UI::PanelMenu.new(x: 400, y: 64, layout: column, scope: 'verbs'))
    verbs.add(UI::PanelButton.new(label: 'use')).on_activated { use }
    verbs.add(UI::PanelButton.new(label: 'drop')).on_activated { drop }
  end

  def fill_bag
    @bag.clear
    @carried.each { |item| @bag.add(UI::IconButton.new(image: item.image, style: SLOT_STYLE)) }
  end

  def use
    report(@used) if @chosen
  end

  def drop
    return unless @chosen

    report(@dropped)
    @carried.delete(@chosen)
    @chosen = nil
    fill_bag
  end

  def report(status)
    @status = status
    @status_item = @chosen
    system!(RGame::Engine::AudioOut).play_sound(CLICK)
  end
end

game = RGame::Game.new(
  root: Inventory.new,
  caption: 'Inventory',
  width: WIDTH,
  height: HEIGHT,
  media_root: ASSETS,
  locales: LOCALES
)

# The panels are nine-slices and the items are images, and each is a Symbol
# naming an atlas element, so all three atlases are registered once.
game.renderer.register_ui_atlas(game.assets.ui_atlas('ui.json'))
game.renderer.register_ui_atlas(game.assets.ui_atlas('skills.json'))
game.renderer.register_ui_atlas(game.assets.ui_atlas('icons.json'))

game.start
