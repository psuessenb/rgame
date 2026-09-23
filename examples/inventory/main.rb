# frozen_string_literal: true

# Inventory — a bag of items in a grid that scrolls, a column of verbs beside it,
# and a second page of key items behind a tab.
#
# Run it:
#
#   ruby examples/inventory/main.rb
#
# The arrow keys (or the d-pad) move through the bag. Right from the end of a row
# crosses into the verbs, and left crosses back. Enter (or A) uses or drops the
# item chosen in the bag. Q and E (or the shoulder buttons) switch between the
# bag and the key items. It exercises:
#   - UI::Tabs — two pages of one screen, and a bar of tabs over them;
#   - UI::Grid with `visible_rows:` — a bag of twenty in three rows, scrolled a
#     row at a time as focus leaves the window;
#   - UI::Stepping across a grid — left and right along a row, up and down along
#     a column, each line wrapping inside itself;
#   - UI::FocusGroup — two menus on one page, and the one of them that reads
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
# it. The panel under the bag keeps the item last focused there, and the verbs
# act on that one. A page's panel is the only place an item's name is drawn.
#
# ## The bag scrolls, and the pages keep their place
#
# The bag shows three of its five rows. Focus leaving the window scrolls it by a
# row, and a wrap from the top row lands on the last and scrolls to the bottom.
# The marks beside the bag are drawn from `rows_above` and `rows_below`. Each
# page keeps its focus and scroll while the other is shown, because the tabs
# update a hidden page and only stop controlling and drawing it.
#
# ## What this example does not solve
#
# The bag holds what its window scrolls through: no stacks of one item, and no
# sorting. Using an item changes nothing but the status line, and a key item
# does nothing at all.

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

WIDTH  = 640
HEIGHT = 480
ASSETS = File.expand_path('../assets', __dir__)
LOCALES = File.expand_path('locales', __dir__) # the text on screen: locales/en.yml

# One thing a page holds: its name, a translation under `items`, and its
# picture, an entry of skills.json's or icons.json's `images`.
class Item
  attr_reader :name, :image

  def initialize(key, image)
    @name = RGame::Engine::Text.new(key.to_s, scope: 'items')
    @image = image
  end
end

# The panel under a page's menu. It names the item last focused there, and
# keeps it while focus is in another menu.
class NamePanel < RGame::Engine::Node2D
  attr_accessor :item

  def initialize(menu:, items:, **)
    super(**)
    @menu = menu
    @items = items
    @item = nil
    @nothing = RGame::Engine::Text.new('panel.nothing')
  end

  def _update(_dt)
    @item = @items[@menu.focused_index] if @menu.focused
  end

  def _draw(renderer, _view)
    renderer.nine_slice(:panel, 0, 0, 306, 56)
    renderer.text(@item ? @item.name : @nothing, 16, 18)
  end
end

# An arrow above a menu while rows are out of view above it, and one below while
# rows are out of view below.
class ScrollMarks < RGame::Engine::Node2D
  COLOR = RGame::Util::Color::LIGHT_GRAY

  def initialize(menu:, **)
    super(**)
    @menu = menu
  end

  def _draw(renderer, _view)
    renderer.triangle(0, 12, 8, 0, 16, 12, color: COLOR) if @menu.rows_above.positive?
    bottom = @menu.bounds_height
    renderer.triangle(0, bottom - 12, 16, bottom - 12, 8, bottom, color: COLOR) if @menu.rows_below.positive?
  end
end

# The tabs, the two pages under them, and the status line.
class Inventory < RGame::Engine::Node2D
  UI = RGame::Engine::UI

  SLOT = 64
  ITEMS = {
    wand: :wand, wrench: :wrench, torch: :torch, hammer: :hammer,
    watering_can: :watering_can, star: :star, trophy: :trophy, gear: :gear,
    oak_staff: :wand, spanner: :wrench, lantern: :torch, mallet: :hammer,
    copper_can: :watering_can, star_shard: :star, silver_cup: :trophy, cog: :gear,
    birch_wand: :wand, pipe_wrench: :wrench, candle: :torch, sledgehammer: :hammer
  }.freeze
  KEY_ITEMS = { house_key: :home, cellar_key: :locked, music_box: :music_on, horn: :audio_on }.freeze
  SLOT_STYLE = UI::ShapeStyle.new
  CLICK = 'blip.ogg'

  def initialize(**)
    super
    @carried = ITEMS.map { |key, image| Item.new(key, image) }
    @help = RGame::Engine::Text.new('help.keys')
    @ready = RGame::Engine::Text.new('status.ready')
    @used = RGame::Engine::Text.new('status.used', :item)
    @dropped = RGame::Engine::Text.new('status.dropped', :item)
    @status = @ready
    @status_item = nil
    tabs = add_node(UI::Tabs.new(x: 16, y: 40, layout: UI::Row.new(item_width: 120, item_height: 28), scope: 'tabs'))
    tabs.add(UI::PanelButton.new(label: 'items'), bag_page)
    tabs.add(UI::PanelButton.new(label: 'key_items'), key_page)
    fill_bag
  end

  def _update(_dt)
    @status.with(item: @status_item.name.to_s) if @status_item
  end

  def _draw(renderer, _view)
    renderer.text(@help, 16, 12)
    renderer.text(@status, 16, HEIGHT - 32)
  end

  private

  def bag_page
    page = RGame::Engine::Node2D.new
    group = page.add_node(UI::FocusGroup.new)
    grid = UI::Grid.new(columns: 4, item_width: SLOT, item_height: SLOT, spacing: 6, visible_rows: 3)
    @bag = group.add_node(UI::PanelMenu.new(x: 16, y: 32, layout: grid))
    verbs = group.add_node(UI::PanelMenu.new(x: 384, y: 32, layout: UI::Column.new(item_width: 160, item_height: 32),
                                             scope: 'verbs'))
    verbs.add(UI::PanelButton.new(label: 'use')).on_activated { use }
    verbs.add(UI::PanelButton.new(label: 'drop')).on_activated { drop }
    page.add_node(ScrollMarks.new(menu: @bag, x: 314, y: 32))
    @bag_panel = page.add_node(NamePanel.new(menu: @bag, items: @carried, y: 272))
    page
  end

  def key_page
    page = RGame::Engine::Node2D.new
    keys = KEY_ITEMS.map { |key, image| Item.new(key, image) }
    grid = UI::Grid.new(columns: 4, item_width: SLOT, item_height: SLOT, spacing: 6)
    menu = page.add_node(UI::PanelMenu.new(x: 16, y: 32, layout: grid))
    keys.each { |item| menu.add(UI::IconButton.new(image: item.image, style: SLOT_STYLE)) }
    page.add_node(NamePanel.new(menu: menu, items: keys, y: 272))
    page
  end

  def fill_bag
    @bag.clear
    @carried.each { |item| @bag.add(UI::IconButton.new(image: item.image, style: SLOT_STYLE)) }
  end

  def use
    report(@used) if @bag_panel.item
  end

  def drop
    return unless @bag_panel.item

    report(@dropped)
    @carried.delete(@bag_panel.item)
    @bag_panel.item = nil
    fill_bag
  end

  def report(status)
    @status = status
    @status_item = @bag_panel.item
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
