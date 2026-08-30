# frozen_string_literal: true

# Game menu — a menu that opens over a world which keeps running.
#
# Run it:
#
#   ruby examples/game_menu/main.rb
#
# Walk with the arrow keys / WASD / a gamepad. Escape (or B) opens the menu;
# up and down move the focus, Enter or A activates, Escape closes. It exercises:
#   - PlayerLayer — one player's own region of the screen, above the world;
#   - UI::Menu / UI::MenuItem — a focused list, navigated without a pointer;
#   - Node2D#paused — one node stops while the rest of the tree carries on;
#   - Node2D#draw_children — the seam that hides a subtree without unbuilding it;
#   - renderer.nine_slice — chrome drawn at any size from one small piece of art.
#
# ## The thing to watch
#
# **The villagers keep walking while your menu is open.** Only the hero stops,
# because pausing is a property of a *node*, not of the world: `hero.paused =
# true` halts that node's `control` and `update` and everything below it, and
# nothing else in the tree notices. That is what lets two players each open
# their own menu while the shared world runs on — `test_projects/tiled_world`
# does exactly that, and this is the single-player shape of it.
#
# The hero and the villagers are the same three components with a different
# controller in the middle: PlayerController reads the player's actions,
# WanderController rolls its own directions. Nothing else about them differs.
#
# ## What this example does not solve
#
# Layout. The menu sits at a fixed margin inside the player's region, because
# centring needs the region's size and that only arrives at draw time. See
# docs/api/ui.md, "What this is not" — the UI package is focus and activation,
# and no more than that yet.

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

WIDTH  = 640
HEIGHT = 480
ASSETS = File.expand_path('../assets', __dir__)

SHEET       = 'hero.json'
HERO_SPEED  = 90.0
NPC_SPEED   = 55.0
NPC_SPAWNS  = [[140, 120], [430, 170], [220, 330], [480, 360]].freeze

# Seeded so the villagers wander the same way every run and two driven runs can
# be compared. `tools/drive_test_project.rb --seed N` overrides it.
DEFAULT_SEED = 0x6E11

# A walker that stays inside the window. Both the hero and the villagers are
# this; only the controller hung on them differs.
class Walker < RGame::Engine::Node2D
  def on_update(_dt)
    self.x = x.clamp(0, WIDTH - width)
    self.y = y.clamp(0, HEIGHT - height)
  end
end

# The pause menu: a panel, a Menu inside it, and the hero it stops.
#
# It lives inside a PlayerLayer, so three things are already true without this
# class arranging any of them — it draws in that player's region, its
# coordinates are relative to that region, and the input it reads is that
# player's. Nothing here mentions viewports or players.
class GameMenu < RGame::Engine::Node2D
  PADDING     = 16
  ITEM_WIDTH  = 180
  ITEM_HEIGHT = 34
  SPACING     = 8
  ITEM_COUNT  = 3

  def initialize(hero:, **)
    super(**)
    @hero = hero
    @open = false
  end

  def on_add
    @menu = add_node(RGame::Engine::UI::Menu.new(
                       x: PADDING, y: PADDING,
                       item_width: ITEM_WIDTH, item_height: ITEM_HEIGHT, spacing: SPACING
                     ))
    @menu.add_item('Resume').on_activated { close }
    # Disabled, so the example shows that state of the art — and because saving
    # is `examples/save_load`'s subject rather than this one's.
    @menu.add_item('Save game', enabled: false)
    @menu.add_item('Quit').on_activated { root.context.close }
    @menu.paused = true # closed: it neither ticks nor draws until it is opened
  end

  # This node is never paused, which is how the menu below it can be reopened:
  # pausing the Menu stops the Menu, not its parent.
  def on_control(actions)
    toggle if actions.pressed?(:ui_cancel)
  end

  def on_draw(renderer, _view)
    return unless @open

    # No z and no band: this is under a PlayerLayer, so it is already in that
    # player's HUD band, and the Menu is a child so it draws over this panel by
    # being drawn after it.
    renderer.nine_slice(:panel, 0, 0, panel_width, panel_height)
  end

  # The Menu is a child, so skipping the child pass is what hides it. Pausing
  # alone would stop it ticking and leave it on screen.
  def draw_children(renderer, view)
    super if @open
  end

  private

  def toggle = @open ? close : open

  def open
    @open = true
    @menu.paused = false
    @hero.paused = true # only the hero: the villagers walk on
  end

  def close
    @open = false
    @menu.paused = true
    @hero.paused = false
  end

  def panel_width = ITEM_WIDTH + (PADDING * 2)
  def panel_height = (ITEM_HEIGHT * ITEM_COUNT) + (SPACING * (ITEM_COUNT - 1)) + (PADDING * 2)
end

class Scene < RGame::Engine::Node2D
  MENU_MARGIN = 40

  def initialize
    super
    @rng = Random.new(ENV.fetch('RGAME_SEED', DEFAULT_SEED).to_i)
  end

  def on_add
    hero = add_node(walker(RGame::Engine::Components::PlayerController.new,
                           HERO_SPEED, WIDTH / 2, HEIGHT / 2))
    NPC_SPAWNS.each do |x, y|
      add_node(walker(RGame::Engine::Components::WanderController.new(rng: @rng), NPC_SPEED, x, y))
    end

    # The player's own layer, and the menu inside it. With one seat this covers
    # the whole window; with two it would be half of it, and nothing here or in
    # GameMenu would change.
    player = root.system(RGame::Engine::Players).primary
    layer = add_node(RGame::Engine::PlayerLayer.new(player: player))
    layer.add_node(GameMenu.new(hero: hero, x: MENU_MARGIN, y: MENU_MARGIN))
  end

  def on_draw(renderer, _view)
    renderer.text('Walk with the arrow keys — Escape opens the menu', 12, 12)
  end

  private

  def walker(controller, speed, x, y)
    node = Walker.new(x: x, y: y)
    node.add_component(RGame::Engine::Components::AnimatedSprite.new(sheet: SHEET))
    node.add_component(RGame::Engine::Components::CharacterBody.new(speed: speed))
    node.add_component(controller)
    node
  end
end

game = RGame::Game.new(
  root: Scene.new,
  caption: 'Game menu',
  width: WIDTH,
  height: HEIGHT,
  media_root: ASSETS
)

# The one thing that has to be registered by hand: a nine-slice id names an
# *element of an atlas*, not a file, so there is nothing for the asset manager
# to resolve `:panel` to on demand. Registering the atlas binds every element in
# it under its own name.
game.renderer.register_ui_atlas(game.assets.ui_atlas('ui.json'))

game.start
