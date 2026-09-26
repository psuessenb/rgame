# frozen_string_literal: true

# Radial menu — a quick menu of icons, chosen by pointing rather than by stepping
# through a list.
#
# Run it:
#
#   ruby examples/radial_menu/main.rb
#
# Point the left stick at an icon and press A. On a keyboard, hold the arrow
# keys — two at once for a diagonal — and press Enter or Space. The chosen icon
# appears, doubled, in the middle of the wheel. It exercises:
#   - UI::RadialMenu — a UI::Menu that builds its own UI::Ring and
#     UI::Pointing, and draws the backdrop, the dead zone and the pointer;
#   - UI::IconButton — each entry, a picture tinted by its state;
#   - UI::ShapeStyle — the disc behind every icon, outlined while focused;
#   - `ui_radial_x` / `ui_radial_y` — the two axes Pointing reads, from the
#     universal set every InputMap carries, so nothing here declares an action;
#   - a UI atlas's `images` — the eight icons, cut from one strip and registered
#     by name in one call.
#
# ## The direction is the selection
#
# A list menu moves focus *relative* to where it already is: down means "the
# next one". A stick is bad at that and good at pointing, so here nothing is
# stepped through at all. Whichever button lies closest to the direction the
# stick points in is focused, which on a ring cuts the circle into one sector per
# button, centred on it. Eight buttons is the number that makes a keyboard a
# first-class input too: the arrow keys, alone and in pairs, produce exactly
# eight directions, one per icon.
#
# That is the only thing that makes this a wheel rather than a list. The menu,
# its buttons and what confirming does are the same classes `examples/game_menu`
# uses; a RadialMenu is a UI::Menu handed a UI::Ring where that one has a
# UI::Column, and UI::Pointing where that one keeps the default UI::Stepping.
#
# `examples/quick_wheel` is the other common style of the same wheel: closed until
# a button is held, and chosen by letting that button go.
#
# ## Letting go selects nothing
#
# The lighter disc around the middle is the **dead zone**, drawn to scale: the
# pointer's tip inside it means the stick is not deflected far enough to mean
# anything, and no button is focused. That is what makes the obvious mistake
# impossible — a player who lets the stick spring back and then presses A has
# not asked for whatever the stick passed over on its way home, and gets nothing.
#
# It is a length on the combined vector, and much bigger than the per-axis dead
# zone every action already has. That one only stops a worn stick drifting; it
# would let a stick barely off centre choose.
#
# **Locked** is disabled, and pointing at it focuses nothing — the same rule a
# list follows by skipping it.
#
# ## White art, coloured by a tint
#
# The icons are white, and IconButton draws each one multiplied by a colour for
# its state — grey at rest, white while focused, dim while disabled — so one
# picture serves all four looks. Dark art would take none of them. While pressed
# the disc is gold, and the disc's ShapeStyle says the icon goes dark on it: what
# reads on a fill is the style's to decide, since it chose the fill.
#
# The icons are 50 pixels in 64-pixel slots and the chosen one is drawn at scale
# 2: images sample nearest-neighbour, so only a whole-number scale stays sharp.
#
# ## What this example does not solve
#
# Captions. The icons carry no text, so the wheel says what was chosen only in
# the line along the bottom. The wheel is also at a fixed position rather than
# centred on the view, because its buttons are placed when they are added and the
# view's size only exists at draw time — the same limit `examples/game_menu`
# names.

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

# The example's own module. `Engine`, `Util`, `UI` and `Components` inside it
# stand for rgame's namespaces of the same names, and every name the example
# defines stays off the top level. docs/api/README.md says why, under "A game's
# own module".
module RadialMenuExample
  Engine = RGame::Engine
  Util = RGame::Util
  UI = Engine::UI
  Components = Engine::Components

  WIDTH  = 640
  HEIGHT = 480
  ASSETS = File.expand_path('../assets', __dir__)
  LOCALES = File.expand_path('locales', __dir__) # the text on screen: locales/en.yml

  # The wheel and what it chooses. The wheel itself — backdrop, dead zone, pointer
  # and buttons — is a UI::RadialMenu; the chosen icon is a node added after it,
  # because between nodes the tree decides what lands on top, and anything this
  # node drew itself would sit under the menu's backdrop.
  class QuickMenu < Engine::Node2D
    RADIUS = 150
    SLOT = 64

    # Clockwise from the top. Each image names an entry of icons.json's `images`.
    ICONS = [
      %i[home home],
      %i[settings gear],
      %i[save save],
      %i[favourite star],
      %i[trophies trophy],
      %i[sound audio_on],
      %i[music music_on],
      %i[locked locked]
    ].freeze

    DISC = UI::ShapeStyle.new(shape: :disc)

    attr_reader :chosen, :chosen_image

    def initialize(**)
      super
      @chosen = nil
      @chosen_image = nil
      @menu = add_node(UI::RadialMenu.new(radius: RADIUS, button_width: SLOT))
      ICONS.each { |key, image| add_icon(key, image) }
      add_node(ChosenIcon.new(menu: self))
    end

    private

    def add_icon(key, image)
      button = @menu.add(UI::IconButton.new(image: image, style: DISC, enabled: image != :locked))
      button.on_activated do
        @chosen = key
        @chosen_image = image
      end
    end
  end

  # The chosen icon, doubled, in the middle of the wheel.
  class ChosenIcon < Engine::Node2D
    SCALE = 2

    def initialize(menu:, **)
      super(**)
      @menu = menu
    end

    def _draw(renderer, _view)
      image = @menu.chosen_image
      renderer.image(image, 0, 0, scale: SCALE) if image
    end
  end

  # The captions. Added after the wheel, so it draws last and its final line is
  # the last text of every frame — which is what the drive script reads.
  class Caption < Engine::Node2D
    NAMES = QuickMenu::ICONS.to_h { |key, _| [key, Engine::Text.new(key, scope: 'items')] }.freeze

    def initialize(menu:, **)
      super(**)
      @menu = menu
      @help = Engine::Text.new('help.point')
      @nothing = Engine::Text.new('status.nothing')
      @chosen = Engine::Text.new('status.chosen', :item)
    end

    def _draw(renderer, _view)
      renderer.text(@help, 12, 12)
      chosen = @menu.chosen
      renderer.text(chosen ? @chosen.with(item: NAMES.fetch(chosen).to_s) : @nothing, 12, HEIGHT - 30)
    end
  end

  class Scene < Engine::Node2D
    def _enter_tree
      menu = add_node(QuickMenu.new(x: WIDTH / 2, y: (HEIGHT / 2) + 6))
      add_node(Caption.new(menu: menu))
    end
  end

  # Builds the game and runs it until the window closes.
  def self.start
    game = RGame::Game.new(
      root: Scene.new,
      caption: 'Radial menu',
      width: WIDTH,
      height: HEIGHT,
      media_root: ASSETS,
      locales: LOCALES
    )

    # An image id that is a Symbol is a name rather than a path, so the icons are
    # registered once, by hand: the atlas cuts each from the strip and registers it
    # under its name.
    game.renderer.register_ui_atlas(game.assets.ui_atlas('icons.json'))

    game.start
  end
end

RadialMenuExample.start
