# frozen_string_literal: true

# Walk — a player-controlled sprite, and the smallest complete game there is.
#
# Run it:
#
#   ruby examples/walk/main.rb
#
# Arrow keys, WASD, a d-pad or a left stick; they all work and none of them are
# mentioned below. It exercises:
#   - Node2D — the scene tree, and `on_update`/`on_draw` as blank hooks;
#   - Components::AnimatedSprite — directional animation off a sprite sheet;
#   - Components::CharacterBody — an intent in -1..1 becomes a step at a speed;
#   - Components::PlayerController — input axes become that intent;
#   - InputMap.default — physical keys become the :move_x / :move_y actions.
#
# ## The shape to take away
#
# The hero is a plain Node2D with three components on it. Nothing subclasses a
# "player" class, and the three components do not know about each other: the
# controller writes a movement intent, the body turns intent into a step, and
# the sprite reads the same intent back to pick which way to face. Swapping the
# controller for Components::WanderController is the whole of turning this into
# an NPC.
#
# The one subclass here is Hero, and it exists only to keep the walker on
# screen — see the comment on `on_update`.

# lib/ on the load path, so `require 'rgame/game'` resolves the same way it
# would from an installed gem. examples/ and lib/ are siblings in both, so this
# line is correct either way.
$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

WIDTH  = 640
HEIGHT = 480
ASSETS = File.expand_path('../assets', __dir__)

SPEED = 90.0 # pixels per second

# A Node2D that stays inside the window.
#
# Clamping is not something the engine does for you here: a plain CharacterBody
# moves the node wherever the intent points, because it is meant for an actor in
# a world with nothing to bump into. Giving it edges is one `on_update` — and in
# a real game it is usually Components::TileWorld doing it instead, which is
# what `examples/scroll_map` shows.
class Hero < RGame::Engine::Node2D
  # `on_update` is the blank hook: Node2D#update does the bookkeeping and calls
  # this, so there is no `super` to forget.
  def on_update(_dt)
    self.x = x.clamp(0, WIDTH - width)
    self.y = y.clamp(0, HEIGHT - height)
  end
end

# The root. It builds the hero in `initialize`, before anything is in the tree.
#
# That matters and is easy to get wrong the other way round: `add_component`
# attaches immediately once its node is live, and AnimatedSprite's attach looks
# for a CharacterBody sibling. Build the node whole, then add it — then the
# order components go on in cannot matter.
class Root < RGame::Engine::Node2D
  def initialize
    super
    add_node(build_hero)
  end

  def on_draw(renderer, _view)
    renderer.text('Arrow keys / WASD / gamepad to walk', 12, 12)
  end

  private

  def build_hero
    hero = Hero.new(x: (WIDTH - 16) / 2, y: (HEIGHT - 22) / 2)
    # The sheet is a path relative to the asset manager's root, resolved on
    # attach — nothing is loaded or registered by hand. hero.json names its own
    # image and its animations; AnimatedSprite picks between them by reading the
    # body's intent, so :walk_left and friends are looked up by name.
    hero.add_component(RGame::Engine::Components::AnimatedSprite.new(sheet: 'hero.json'))
    hero.add_component(RGame::Engine::Components::CharacterBody.new(speed: SPEED))
    hero.add_component(RGame::Engine::Components::PlayerController.new)
    hero
  end
end

game = RGame::Game.new(
  root: Root.new,
  caption: 'Walk',
  width: WIDTH,
  height: HEIGHT,
  media_root: ASSETS
)

game.start
