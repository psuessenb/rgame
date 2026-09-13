# frozen_string_literal: true

# Radial menu — choosing by pointing rather than by stepping through a list.
#
# Run it:
#
#   ruby examples/radial_menu/main.rb
#
# Point the left stick at a colour and press A. On a keyboard, hold the arrow
# keys — two at once for a diagonal — and press Enter or Space. The chosen
# colour fills the middle of the wheel. It exercises:
#   - UI::RadialMenu — a UI::Menu that builds its own UI::Ring and
#     UI::Pointing, and draws the backdrop, the dead zone and the pointer;
#   - UI::Ring — its layout, items spaced round a circle;
#   - UI::Pointing — its navigation, focus chosen by the direction of a stick;
#   - `ui_radial_x` / `ui_radial_y` — the two axes Pointing reads, from the
#     universal set every InputMap carries, so nothing here declares an action.
#
# ## The direction is the selection
#
# A list menu moves focus *relative* to where it already is: down means "the
# next one". A stick is bad at that and good at pointing, so here nothing is
# stepped through at all. Whichever item lies closest to the direction the stick
# points in is focused, which on a ring cuts the circle into one sector per item,
# centred on it. Eight items is the number that makes a keyboard a first-class
# input too: the arrow keys, alone and in pairs, produce exactly eight
# directions, one per colour.
#
# That is the only thing that makes this a wheel rather than a list. The menu,
# its items and what confirming does are the same classes `examples/game_menu`
# uses; a RadialMenu is a UI::Menu handed a UI::Ring where that one has a
# UI::Column, and UI::Pointing where that one keeps the default UI::Stepping.
#
# ## Letting go selects nothing
#
# The lighter disc around the middle is the **dead zone**, drawn to scale: the
# pointer's tip inside it means the stick is not deflected far enough to mean
# anything, and no item is focused. That is what makes the obvious mistake
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
# ## What this example does not solve
#
# Icons. A real wheel usually shows pictures rather than words, and the
# mechanism is exactly the same with a sprite where a label is. The wheel is also
# at a fixed position rather than centred on the view, because its items are
# placed when they are added and the view's size only exists at draw time — the
# same limit `examples/game_menu` names.

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

WIDTH  = 640
HEIGHT = 480
ASSETS = File.expand_path('../assets', __dir__)

# The wheel and what it chooses. The wheel itself — backdrop, dead zone, pointer
# and buttons — is a UI::RadialMenu; the swatch is a node added after it, because
# between nodes the tree decides what lands on top, and anything this node drew
# itself would sit under the menu's backdrop.
class ColourWheel < RGame::Engine::Node2D
  Color = RGame::Util::Color

  RADIUS = 150
  ITEM_WIDTH = 96
  ITEM_HEIGHT = 30

  COLOURS = [
    ['Red', Color.new(214, 64, 56)],
    ['Orange', Color.new(232, 140, 48)],
    ['Yellow', Color.new(236, 208, 72)],
    ['Green', Color.new(92, 176, 84)],
    ['Teal', Color.new(56, 164, 164)],
    ['Blue', Color.new(64, 104, 204)],
    ['Purple', Color.new(140, 84, 188)],
    ['Locked', nil]
  ].freeze

  NOTHING_CHOSEN = Color.new(24, 22, 28)

  attr_reader :chosen, :swatch

  def initialize(**)
    super
    @chosen = nil
    @swatch = NOTHING_CHOSEN
    @menu = add_node(RGame::Engine::UI::RadialMenu.new(radius: RADIUS, button_width: ITEM_WIDTH,
                                                       button_height: ITEM_HEIGHT, padding: 0))
    COLOURS.each { |label, colour| add_colour(label, colour) }
    add_node(Swatch.new(wheel: self))
  end

  private

  def add_colour(label, colour)
    button = @menu.add(RGame::Engine::UI::PanelButton.new(label: label, enabled: !colour.nil?))
    button.on_activated do
      @chosen = label
      @swatch = colour
    end
  end
end

# The chosen colour, filling the middle of the wheel.
class Swatch < RGame::Engine::Node2D
  RADIUS = 34

  def initialize(wheel:, **)
    super(**)
    @wheel = wheel
  end

  def on_draw(renderer, _view) = renderer.circle(0, 0, RADIUS, color: @wheel.swatch)
end

# The captions. Added after the wheel, so it draws last and its final line is
# the last text of every frame — which is what the drive script reads.
class Caption < RGame::Engine::Node2D
  STATUS = Hash.new('Chosen: nothing yet').merge(
    ColourWheel::COLOURS.to_h { |label, _| [label, "Chosen: #{label}"] }
  ).freeze

  def initialize(wheel:, **)
    super(**)
    @wheel = wheel
  end

  def on_draw(renderer, _view)
    renderer.text('Point the stick (or arrow keys) at a colour, then press A (or Enter)', 12, 12)
    renderer.text(STATUS[@wheel.chosen], 12, HEIGHT - 30)
  end
end

class Scene < RGame::Engine::Node2D
  def on_add
    wheel = add_node(ColourWheel.new(x: WIDTH / 2, y: (HEIGHT / 2) + 6))
    add_node(Caption.new(wheel: wheel))
  end
end

game = RGame::Game.new(
  root: Scene.new,
  caption: 'Radial menu',
  width: WIDTH,
  height: HEIGHT,
  media_root: ASSETS
)

# The buttons are PanelButtons, which draw their four states as nine-slices, and a
# nine-slice id names an element of an atlas rather than a file — so the atlas is
# registered once, by hand.
game.renderer.register_ui_atlas(game.assets.ui_atlas('ui.json'))

game.start
