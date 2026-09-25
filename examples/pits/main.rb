# frozen_string_literal: true

# Pits — falling into a gap, hopping across one, and coming back.
#
# Run it:
#
#   ruby examples/pits/main.rb
#
# Arrow keys, WASD, a d-pad or a left stick walk the hero; Space or the pad's A
# button hops. C or the pad's Y turns coyote time off and on. It exercises:
#   - TileMap gap tiles — `pits.tsx` gives its tiles the class `gap`, and a cell
#     holding one has no floor;
#   - Components::Footing — the fall into a gap, and the coyote time before it;
#   - Components::Respawn — the way back to where the hero first stood, flashing;
#   - Components::Hop — the jump a node in the air crosses a gap with;
#   - Node2D#scale — the shrink into the gap, drawn about the hero's feet;
#   - Components::TileWorld, Components::CharacterBody and
#     Components::FeetCollider — the map, the walking and the box whose centre
#     stands on the floor.
#
# ## Floor is where there is no gap
#
# Walk south into the chasm. Once the middle of the hero's feet box is over a
# gap tile, the hero stops, shrinks toward their feet and comes back on the
# spot they started from, blinking for a second. They can walk at once: the
# blink only shows where they came back. Nothing here decides any of that. The
# map says where the gaps are, `Footing` watches the feet, and `Respawn` holds
# the spot.
#
# Hop across a trench instead. A hero in the air never falls, so a hop that
# lands on the far side crosses, and one that lands in the trench falls there.
#
# ## Coyote time
#
# Walk off the edge of a trench and hop a moment later: the hop still counts, as
# long as it comes within a tenth of a second of the step off. The bar under the
# help lines is that tenth of a second running out. Press C and try again: with
# no coyote time the hero drops on the first tick off the edge, and the same
# late hop is too late.
#
# ## What this does not solve
#
# **A fall costs nothing.** `Footing#on_fell` is where a game takes a life, and
# this one takes none. **The spot never moves.** `Respawn#set_point` moves it,
# which is what a checkpoint would call. **The pit's edges are drawn on one
# side only.** Its north edge has a tile of its own, and the other three meet
# the grass directly.

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

WIDTH  = 640
HEIGHT = 480
ASSETS = File.expand_path('../assets', __dir__)
LOCALES = File.expand_path('locales', __dir__) # the text on screen: locales/en.yml

MAP   = 'pits.tmx'
SPEED = 80.0 # px/s

# The hop from `examples/jump_topdown`: half a second at walking speed carries the
# hero 40px, across a one-tile trench from anywhere near its edge.
HOP_PEAK = 18.0
HOP_DURATION = 0.5

# Celeste's grace time: six ticks at 60 a second.
COYOTE = 0.1

FEET_WIDTH  = 12
FEET_HEIGHT = 6

Controls = RGame::Util::Controls

# A walker that hops, falls and comes back. Every part of that is a component;
# the hero only turns coyote time off and on.
class Hero < RGame::Engine::Node2D
  attr_reader :footing

  def initialize(**)
    super
    add_component(RGame::Engine::Components::AnimatedSprite.new(sheet: 'hero.json'))
    add_component(RGame::Engine::Components::FeetCollider.new(width: FEET_WIDTH, height: FEET_HEIGHT))
    add_component(RGame::Engine::Components::CharacterBody.new(speed: SPEED, blocked_by: [:tiles]))
    add_component(RGame::Engine::Components::PlayerController.new)
    add_component(RGame::Engine::Components::Hop.new(peak: HOP_PEAK, duration: HOP_DURATION))
    @footing = add_component(RGame::Engine::Components::Footing.new(coyote: COYOTE))
    add_component(RGame::Engine::Components::Respawn.new(flash: 1.0))
  end

  def _control(actions)
    @footing.coyote = @footing.coyote.zero? ? COYOTE : 0 if actions.pressed?(:coyote)
  end
end

# The map, the hero on its `start` point, and the help over them. It draws the
# help and the coyote bar itself, in the `:overlay` band, once across the window
# over everything else.
class Scene < RGame::Engine::Node2D
  COYOTE_STATE = { true => RGame::Engine::Text.new('status.coyote_on'),
                   false => RGame::Engine::Text.new('status.coyote_off') }.freeze

  BAR_X = 12
  BAR_Y = 84
  BAR_WIDTH = 120
  BAR_HEIGHT = 6
  BAR_EMPTY = RGame::Util::Color.rgba(0, 0, 0, 120)
  BAR_FULL = RGame::Util::Color.rgba(255, 214, 90, 255)

  def initialize
    super(band: :overlay)
    @help_walk = RGame::Engine::Text.new('help.walk')
    @help_fall = RGame::Engine::Text.new('help.fall')
    @help_coyote = RGame::Engine::Text.new('help.coyote')
  end

  def _enter_tree
    map = root.context.assets.tilemap(MAP).map
    players = root.system(RGame::Engine::Players)
    add_component(RGame::Engine::Components::TileWorld.new(
                    map: map, tilemap_id: MAP, cameras: players.map(&:camera)
                  ))

    start = map.object_named('start')
    view = add_node(RGame::Engine::WorldView.new)
    actors = RGame::Engine::TileMapLayer.mount(view)[:actors]
    @hero = actors.add_node(Hero.new(x: start.x, y: start.y))
  end

  # The bar is `coyote_left` as a share of the full coyote time: full while the
  # hero stands, running down off an edge, empty in the air and with coyote time
  # off.
  def _draw(renderer, _view)
    renderer.text(@help_walk, 12, 12)
    renderer.text(@help_fall, 12, 34)
    renderer.text(@help_coyote, 12, 56)
    footing = @hero.footing
    renderer.text(COYOTE_STATE[footing.coyote.positive?], 140, 78)
    renderer.rect(BAR_X, BAR_Y, BAR_WIDTH, BAR_HEIGHT, color: BAR_EMPTY)
    return if footing.coyote.zero?

    renderer.rect(BAR_X, BAR_Y, BAR_WIDTH * footing.coyote_left / footing.coyote, BAR_HEIGHT, color: BAR_FULL)
  end
end

game = RGame::Game.new(
  root: Scene.new,
  caption: 'Pits',
  width: WIDTH,
  height: HEIGHT,
  media_root: ASSETS,
  locales: LOCALES,
  # :jump and :coyote are this game's own actions. Space is also in the default
  # map as :fire and :ui_confirm, and Y as :grab, which nothing here reads.
  input_map: RGame::Engine::InputMap.default.merge(
    jump: { buttons: [Controls::KEY_SPACE, Controls::PAD_A] },
    coyote: { buttons: [Controls::KEY_C, Controls::PAD_Y] }
  )
)

game.start
