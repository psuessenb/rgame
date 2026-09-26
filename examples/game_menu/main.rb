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
#   - UI::PanelMenu / UI::PanelButton — a focused list on a panel that sizes
#     itself to the buttons, navigated without a pointer;
#   - UI::Menu#open / #close — a menu that is built once and shown when wanted;
#   - Node2D#paused — one node stops while the rest of the tree carries on;
#   - renderer.nine_slice — chrome drawn at any size from one small piece of art.
#
# ## The thing to watch
#
# **The villagers keep walking while your menu is open.** Only the hero stops,
# because pausing is a property of a *node*, not of the world: `hero.paused =
# true` halts that node's `control` and `update` and everything below it, and
# nothing else in the tree notices. That is what lets two players each open
# their own menu while the shared world runs on, and this is the single-player
# shape of it.
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

# The example's own module. `Engine` and `Util` inside it are short for
# `RGame::Engine` and `RGame::Util`, and every name the example defines stays off
# the top level. docs/api/README.md says why, under "A game's own module".
module GameMenuExample
  Engine = RGame::Engine
  Util = RGame::Util

  WIDTH  = 640
  HEIGHT = 480
  ASSETS = File.expand_path('../assets', __dir__)
  LOCALES = File.expand_path('locales', __dir__) # the text on screen: locales/en.yml

  SHEET       = 'hero.json'
  HERO_SPEED  = 90.0
  NPC_SPEED   = 55.0
  NPC_SPAWNS  = [[148, 142], [438, 192], [228, 352], [488, 382]].freeze

  # Seeded so the villagers wander the same way every run and two driven runs can
  # be compared. `tools/drive_test_project.rb --seed N` overrides it.
  DEFAULT_SEED = 0x6E11

  # A walker that stays inside the window. Both the hero and the villagers are
  # this; only the controller hung on them differs.
  class Walker < Engine::Node2D
    # A walker stands on its origin, so the picture reaches half its width to
    # either side and its whole height above.
    def _update(_dt)
      self.x = x.clamp(width / 2.0, WIDTH - (width / 2.0))
      self.y = y.clamp(height, HEIGHT)
    end
  end

  # The pause menu: a PanelMenu, and the hero it stops.
  #
  # It lives inside a PlayerLayer, so three things are already true without this
  # class arranging any of them — it draws in that player's region, its
  # coordinates are relative to that region, and the input it reads is that
  # player's. Nothing here mentions viewports or players.
  class GameMenu < Engine::Node2D
    PADDING     = 16
    ITEM_WIDTH  = 180
    ITEM_HEIGHT = 34
    SPACING     = 8

    def initialize(hero:, **)
      super(**)
      @hero = hero
    end

    def _enter_tree
      column = Engine::UI::Column.new(item_width: ITEM_WIDTH, item_height: ITEM_HEIGHT, spacing: SPACING)
      # The panel reaches PADDING beyond the buttons, so placing the menu PADDING
      # in puts the panel's corner at this node's origin.
      @menu = add_node(Engine::UI::PanelMenu.new(x: PADDING, y: PADDING, padding: PADDING, layout: column,
                                                 scope: 'menu'))
      @menu.add(Engine::UI::PanelButton.new(label: 'resume')).on_activated { close }
      # Disabled, so the example shows that state of the art — and because saving
      # is `examples/save_load`'s subject rather than this one's.
      @menu.add(Engine::UI::PanelButton.new(label: 'save', enabled: false))
      @menu.add(Engine::UI::PanelButton.new(label: 'quit')).on_activated { root.context.close }
      @menu.close # built once, shown when Escape asks for it
    end

    # A closed menu draws nothing and takes no focus or confirm, but its parent
    # still reads Escape, which is what opens it again.
    def _control(actions)
      toggle if actions.pressed?(:ui_cancel)
    end

    private

    def toggle = @menu.open? ? close : open

    def open
      @menu.open
      @hero.paused = true # only the hero: the villagers walk on
    end

    def close
      @menu.close
      @hero.paused = false
    end
  end

  class Scene < Engine::Node2D
    MENU_MARGIN = 40

    def initialize
      super
      @help = Engine::Text.new('help.walk')
    end

    def _enter_tree
      # The hero's 16x22 picture starts with its top-left corner on the window's centre.
      hero = add_node(walker(Engine::Components::PlayerController.new,
                             HERO_SPEED, (WIDTH / 2) + 8, (HEIGHT / 2) + 22))
      NPC_SPAWNS.each do |x, y|
        add_node(walker(Engine::Components::WanderController.new, NPC_SPEED, x, y))
      end

      # The player's own layer, and the menu inside it. With one seat this covers
      # the whole window; with two it would be half of it, and nothing here or in
      # GameMenu would change.
      player = root.system(Engine::Players).primary
      layer = add_node(Engine::PlayerLayer.new(player: player))
      layer.add_node(GameMenu.new(hero: hero, x: MENU_MARGIN, y: MENU_MARGIN))
    end

    def _draw(renderer, _view)
      renderer.text(@help, 12, 12)
    end

    private

    def walker(controller, speed, x, y)
      node = Walker.new(x: x, y: y)
      node.add_component(Engine::Components::AnimatedSprite.new(sheet: SHEET))
      node.add_component(Engine::Components::CharacterBody.new(speed: speed))
      node.add_component(controller)
      node
    end
  end

  # Builds the game and runs it until the window closes.
  def self.start
    game = RGame::Game.new(
      root: Scene.new,
      caption: 'Game menu',
      width: WIDTH,
      height: HEIGHT,
      media_root: ASSETS,
      locales: LOCALES,
      seed: DEFAULT_SEED
    )

    # The one thing that has to be registered by hand: a nine-slice id names an
    # *element of an atlas*, not a file, so there is nothing for the asset manager
    # to resolve `:panel` to on demand. Registering the atlas binds every element in
    # it under its own name.
    game.renderer.register_ui_atlas(game.assets.ui_atlas('ui.json'))

    game.start
  end
end

GameMenuExample.start
