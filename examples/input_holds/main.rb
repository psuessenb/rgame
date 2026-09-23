# frozen_string_literal: true

# Input holds — one button that opens a chest when tapped and searches it when
# held, and a chord that does a third thing.
#
# Run it:
#
#   ruby examples/input_holds/main.rb
#
# Tap E (or A) to open the chest and hold it to search inside. The meter under
# the chest fills while the hold counts down. L (or LB) raises a shield, and
# L and R together (or both shoulder buttons) swap stance — while that chord is
# held the shield drops, because a chord silences the plain actions on its
# buttons. It exercises:
#   - `tap:` — an action that presses on a release that came in time;
#   - `hold:` — an action that presses once its buttons have been down long
#     enough, and stays held until they come up;
#   - `all:` — a chord, held while every one of its ids is down, declared once
#     per device;
#   - Actions#held_for — the seconds behind the meter, which no caller counts
#     for itself;
#   - InputMap.default.merge — the four actions, over the universal UI set.
#
# ## One button, two actions
#
# `open` and `search` name the same button and differ only in what they ask of
# time. A press answers exactly one of them: hold past the tap's threshold and
# the release presses nothing, so the chest is never opened on the way out of a
# search. Nothing here counts a second for itself — the map declares the
# thresholds and ActionMapper measures them against the timestep it polls with.
#
# ## What this example does not solve
#
# Sequences and double taps: a chord is buttons held together, not buttons
# pressed in turn. A prompt for a chord, either — `InputMap#button_for` answers
# nil for one, because two glyphs and a plus sign are a different picture from
# the single glyph `examples/input_glyphs` draws. The meter is also drawn at a
# fixed position rather than centred on the view, which is what keeps it beside
# the chest it belongs to.

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

WIDTH  = 640
HEIGHT = 480
ASSETS = File.expand_path('../assets', __dir__)
LOCALES = File.expand_path('locales', __dir__) # the text on screen: locales/en.yml
Controls = RGame::Util::Controls

# Seconds, and the same numbers the map is built from: the meter draws the hold
# against its own threshold rather than against a number copied out of it.
TAP_WITHIN = 0.3
HOLD_FOR = 0.6

CLICK = 'blip.ogg'

# The chest, its meter, and which of the two actions last reached it.
#
# It reads `pressed?` for both, exactly as it would for a plain button. The
# difference between a tap and a hold is in the map, not here, which is the
# point of declaring them there.
class Chest < RGame::Engine::Node2D
  WIDTH = 96
  HEIGHT = 64
  METER_HEIGHT = 8
  METER_GAP = 12

  BODY = RGame::Util::Color.new(107, 74, 47)
  OPENED = RGame::Util::Color.new(201, 162, 39)
  SEARCHED = RGame::Util::Color.new(232, 217, 160)
  METER = RGame::Util::Color.new(79, 163, 209)

  STATE_COLOR = { shut: BODY, open: OPENED, searched: SEARCHED }.freeze

  STATE = {
    shut: RGame::Engine::Text.new('chest.shut'),
    open: RGame::Engine::Text.new('chest.open'),
    searched: RGame::Engine::Text.new('chest.searched')
  }.freeze

  def initialize(**)
    super
    @state = :shut
    @charge = 0.0
  end

  # What the caption draws, so the state is named in one place.
  def caption = STATE.fetch(@state)

  def _control(actions)
    open if actions.pressed?(:open)
    search if actions.pressed?(:search)
    @charge = actions.held_for(:search)
  end

  def _draw(renderer, _view)
    renderer.rect(0, 0, WIDTH, HEIGHT, color: STATE_COLOR.fetch(@state))
    filled = [@charge / HOLD_FOR, 1.0].min * WIDTH
    renderer.rect(0, HEIGHT + METER_GAP, filled, METER_HEIGHT, color: METER)
  end

  private

  def open
    @state = :open
    click
  end

  def search
    @state = :searched
    click
  end

  def click = system!(RGame::Engine::AudioOut).play_sound(CLICK)
end

# The shield and the stance the chord swaps.
#
# `block` is an ordinary held action on one of the chord's buttons, and it reads
# false while the chord is held. Nothing here checks for the chord: the map says
# which actions it covers, and the mapper switches them off.
class Stance < RGame::Engine::Node2D
  SIZE = 56

  SWORD = RGame::Util::Color.new(176, 65, 62)
  SHIELD = RGame::Util::Color.new(62, 111, 176)

  NAME = {
    sword: RGame::Engine::Text.new('stance.sword'),
    shield: RGame::Engine::Text.new('stance.shield')
  }.freeze

  GUARD = {
    true => RGame::Engine::Text.new('status.blocking'),
    false => RGame::Engine::Text.new('status.open')
  }.freeze

  def initialize(**)
    super
    @stance = :sword
    @blocking = false
  end

  def caption = NAME.fetch(@stance)
  def guard = GUARD.fetch(@blocking)

  def _control(actions)
    swap if actions.pressed?(:swap)
    @blocking = actions.held?(:block)
  end

  def _draw(renderer, _view)
    return unless @blocking

    renderer.rect(0, 0, SIZE, SIZE, color: @stance == :sword ? SWORD : SHIELD)
  end

  private

  def swap
    @stance = @stance == :sword ? :shield : :sword
    system!(RGame::Engine::AudioOut).play_sound(CLICK)
  end
end

# The two help lines and the three status lines. Added last and with the chest
# last of all, so the chest's state is the final text of every frame — which is
# what the drive script reads.
class Caption < RGame::Engine::Node2D
  LINE = 22

  def initialize(chest:, stance:, **)
    super(**)
    @chest = chest
    @stance = stance
    @keys = RGame::Engine::Text.new('help.keys')
    @pad = RGame::Engine::Text.new('help.pad')
  end

  def _draw(renderer, _view)
    renderer.text(@keys, 12, 12)
    renderer.text(@pad, 12, 12 + LINE)
    renderer.text(@stance.caption, 12, HEIGHT - (LINE * 3))
    renderer.text(@stance.guard, 12, HEIGHT - (LINE * 2))
    renderer.text(@chest.caption, 12, HEIGHT - LINE)
  end
end

class Scene < RGame::Engine::Node2D
  def _enter_tree
    chest = add_node(Chest.new(x: 80, y: 150))
    stance = add_node(Stance.new(x: 420, y: 150))
    add_node(Caption.new(chest: chest, stance: stance))
  end
end

game = RGame::Game.new(
  root: Scene.new,
  caption: 'Input holds',
  width: WIDTH,
  height: HEIGHT,
  media_root: ASSETS,
  locales: LOCALES,
  input_map: RGame::Engine::InputMap.default.merge(
    open: { buttons: [Controls::KEY_E, Controls::PAD_A], tap: TAP_WITHIN },
    search: { buttons: [Controls::KEY_E, Controls::PAD_A], hold: HOLD_FOR },
    block: { buttons: [Controls::KEY_L, Controls::PAD_LEFT_SHOULDER] },
    swap: { all: [[Controls::KEY_L, Controls::KEY_R],
                  [Controls::PAD_LEFT_SHOULDER, Controls::PAD_RIGHT_SHOULDER]] }
  )
)

game.start
