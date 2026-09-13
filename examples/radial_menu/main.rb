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
#   - UI::RadialMenu — items on a ring, focused by the direction of a stick;
#   - UI::MenuItem — the same item a vertical Menu holds, in four states of art;
#   - `ui_radial_x` / `ui_radial_y` — the two axes it reads, from the universal
#     set every InputMap carries, so nothing here declares an action;
#   - renderer.circle / renderer.line — the backdrop and the pointer.
#
# ## The direction is the selection
#
# A list menu moves focus *relative* to where it already is: down means "the
# next one". A stick is bad at that and good at pointing, so here nothing is
# stepped through at all. The ring is cut into one sector per item, each centred
# on its item, and whichever sector the stick points into is focused. Eight items
# is the number that makes a keyboard a first-class input too: the arrow keys,
# alone and in pairs, produce exactly eight directions, one per colour.
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
# vertical Menu follows by skipping it.
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

# The wheel and what it chooses. Its children are the menu's items, so this
# node's own drawing — backdrop, dead zone, swatch, pointer — lands beneath them.
class ColourWheel < RGame::Engine::Node2D
  Color = RGame::Util::Color

  RADIUS = 150
  ITEM_WIDTH = 96
  ITEM_HEIGHT = 30
  RIM = RADIUS + 44
  SWATCH_RADIUS = 34

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

  BACKDROP = Color.new(44, 40, 52)
  DEAD_ZONE = Color.new(76, 72, 88)
  POINTER = Color.new(240, 236, 224)
  NOTHING_CHOSEN = Color.new(24, 22, 28)

  attr_reader :chosen

  def initialize(**)
    super
    @chosen = nil
    @swatch = NOTHING_CHOSEN
    @menu = add_node(RGame::Engine::UI::RadialMenu.new(radius: RADIUS, item_width: ITEM_WIDTH,
                                                       item_height: ITEM_HEIGHT))
    COLOURS.each { |label, colour| add_colour(label, colour) }
  end

  # All in the wheel's own space, whose origin is the centre of the ring.
  def on_draw(renderer, _view)
    renderer.circle(0, 0, RIM, color: BACKDROP)
    renderer.circle(0, 0, @menu.dead_zone * RADIUS, color: DEAD_ZONE)
    renderer.circle(0, 0, SWATCH_RADIUS, color: @swatch)

    reach = RADIUS / [Math.hypot(@menu.aim_x, @menu.aim_y), 1.0].max
    tip_x = @menu.aim_x * reach
    tip_y = @menu.aim_y * reach
    renderer.line(0, 0, tip_x, tip_y, thickness: 3.0, color: POINTER)
    renderer.circle(tip_x, tip_y, 6, color: POINTER)
  end

  private

  def add_colour(label, colour)
    item = @menu.add_item(label, enabled: !colour.nil?)
    item.on_activated do
      @chosen = label
      @swatch = colour
    end
  end
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

# The items are MenuItems, which draw their four states as nine-slices, and a
# nine-slice id names an element of an atlas rather than a file — so the atlas is
# registered once, by hand.
game.renderer.register_ui_atlas(game.assets.ui_atlas('ui.json'))

game.start
