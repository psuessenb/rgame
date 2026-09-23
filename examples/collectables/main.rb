# frozen_string_literal: true

# Collectables — things that take themselves, and a thing you press to open.
#
# Run it:
#
#   ruby examples/collectables/main.rb
#
# Arrow keys, WASD, a d-pad or a left stick walk. Walk over a coin to take it.
# Stand by the chest and press E — or the pad's X — to open it, and it spills
# three more. It exercises:
#   - Components::Collectable — a coin that collects itself on contact;
#   - Components::Interactor — the nearest thing in range, and the press;
#   - Components::CollisionWorld — the broadphase both of them read;
#   - Engine::Text — the counter, a key with a variable, rendered again only
#     when the count changes.
#
# ## Two ways to reach a thing, and neither is written here
#
# A coin is taken by touching it and the chest is opened by a press, and the
# difference is entirely in what each of them carries. Nothing in the hero knows
# what a coin is: it has a collider on the `:hero` layer and an `Interactor`,
# and the coins do the rest. Adding a fourth kind of pickup is adding a node.
#
# The two components answer different questions on purpose. `Collectable` is
# "something touched me", which is a contact and needs no button. `Interactor`
# is "what would I act on", which is a range query plus a press — and it is a
# `Targeting`, the same component a turret uses to pick what to shoot.
#
# The chest also *stops* the hero, through the `blocked_by: [:interactable]` on
# its CharacterBody — one declaration on the mover, and nothing on the chest. So
# walking into it puts it in reach, which is how a player finds out there is
# something to press.
#
# ## The prompt is drawn from `target`, not from a contact
#
# `interactor.target` is the nearest node in range on the layer, refreshed every
# update and nil when there is nothing. That is what the prompt is drawn over,
# and it is why the prompt appears before the press rather than after it.
#
# This example labels the prompt with a fixed key rather than with the button
# the player's own device would press. `examples/input_glyphs` shows how to ask
# the map that question — `InputMap#button_for` — and it is a whole example on
# its own.
#
# ## What this does not solve
#
# What a coin is *worth* belongs to the game: here the root keeps one Integer
# and every coin adds one to it. An inventory that holds kinds of thing is
# later on the roadmap, and a counter is the honest version of it today.

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

WIDTH  = 640
HEIGHT = 480
ASSETS = File.expand_path('../assets', __dir__)
LOCALES = File.expand_path('locales', __dir__)

Color = RGame::Util::Color

SPEED = 110.0
CELL_SIZE = 64

BACKDROP   = Color.new(28, 30, 38)
COIN       = Color.new(240, 200, 96)
CHEST      = Color.new(150, 104, 56)
CHEST_OPEN = Color.new(86, 70, 52)
PROMPT     = Color.new(240, 236, 224)
HUD        = Color.new(200, 210, 230)

COIN_RADIUS = 7
CHEST_SIZE = 28
REACH = 44.0

# A coin: a shape, and a Collectable that takes it.
#
# The component does everything. `by: :hero` is the layer whose colliders count,
# `sound:` is played through the tree's AudioOut, and the node is freed by
# default — so the whole of "a coin disappears when you walk into it" is the one
# `add_component` below, and `on_collected` is the game's half.
class Coin < RGame::Engine::Node2D
  def initialize(**)
    super
    add_component(RGame::Engine::Components::CircleCollider.new(radius: COIN_RADIUS, layer: :pickup))
    add_component(RGame::Engine::Components::Collectable.new(by: :hero, sound: 'blip.ogg'))
  end

  # The Collectable, so the room can connect its counter to it. `add_component`
  # returns what it was given, which is the usual way to hold one by name.
  def collectable = get_component(RGame::Engine::Components::Collectable)

  def _draw(renderer, _view) = renderer.circle(0, 0, COIN_RADIUS, color: COIN)
end

# A chest: a shape on the `:interactable` layer, and a lid.
#
# It carries no component of its own for the opening — an Interactor on the hero
# finds it by layer and emits it, and `open` is an ordinary method that whatever
# listened calls. Nothing here reads input.
class Chest < RGame::Engine::Node2D
  SPILL = [[-40, 0], [0, -44], [40, 0]].freeze

  def initialize(**)
    super
    add_component(RGame::Engine::Components::BoxCollider.new(width: CHEST_SIZE, height: CHEST_SIZE,
                                                             layer: :interactable))
    @open = false
  end

  def open? = @open

  # Opening spills the coins it held. They are added to this node's parent
  # rather than to the chest, so taking one is the same contact as taking any
  # other coin — a coin does not care who put it there.
  def open
    return if @open

    @open = true
    SPILL.each { |dx, dy| parent.spill(x + dx, y + dy) }
  end

  def _draw(renderer, _view)
    renderer.rect(0, 0, CHEST_SIZE, CHEST_SIZE, color: @open ? CHEST_OPEN : CHEST)
  end
end

# The hero: the walker from `examples/walk`, plus the two things this example
# is about — a collider on the `:hero` layer, which is what a coin waits for,
# and an Interactor, which is what finds the chest.
class Hero < RGame::Engine::Node2D
  def initialize(**)
    super
    add_component(RGame::Engine::Components::AnimatedSprite.new(sheet: 'hero.json'))
    add_component(RGame::Engine::Components::CharacterBody.new(speed: SPEED,
                                                               blocked_by: [:interactable]))
    add_component(RGame::Engine::Components::PlayerController.new)
    add_component(RGame::Engine::Components::BoxCollider.new(width: 16, height: 22, layer: :hero))
    @interactor = add_component(RGame::Engine::Components::Interactor.new(range: REACH,
                                                                          layer: :interactable))
  end

  # What the hero would act on, or nil. The room draws the prompt over it.
  def target = @interactor.target

  def on_interacted(&) = @interactor.on_interacted(&)

  def _update(_dt)
    self.x = x.clamp(0, WIDTH - 16)
    self.y = y.clamp(0, HEIGHT - 22)
  end
end

# The room. It mounts the broadphase, builds everything, and keeps the count.
class Room < RGame::Engine::Node2D
  COINS = [[150, 250], [230, 250], [470, 250], [180, 400], [430, 120], [560, 380]].freeze

  def initialize
    super
    @taken = 0
    @count = RGame::Engine::Text.new('hud.coins', :count)
    @help = RGame::Engine::Text.new('help.walk')
    @prompt = RGame::Engine::Text.new('help.open')
    add_component(RGame::Engine::Components::CollisionWorld.new(cell_size: CELL_SIZE))
  end

  def _enter_tree
    COINS.each { |x, y| spill(x, y) }
    add_node(Chest.new(x: 300, y: 236))
    @hero = add_node(Hero.new(x: 60, y: 240))
    @hero.on_interacted(&:open)
  end

  # One coin, counted when it is taken. Called for the coins the room starts
  # with and for the ones the chest spills, so both are the same coin.
  def spill(x, y)
    coin = add_node(Coin.new(x: x, y: y))
    coin.collectable.on_collected { @taken += 1 }
    coin
  end

  def _draw(renderer, view)
    renderer.rect(0, 0, view.width, view.height, color: BACKDROP)
    renderer.text(@help, 12, 12, color: HUD)
    renderer.text(@count.with(count: @taken), 12, 34, color: HUD)
    draw_prompt(renderer)
  end

  private

  # Over whatever is in reach, in world coordinates — the room draws it rather
  # than the chest, because a prompt is about the hero's state and not the
  # chest's, and every interactable would otherwise need the same code.
  def draw_prompt(renderer)
    target = @hero.target
    return if target.nil? || target.open?

    renderer.text(@prompt, target.x - 24, target.y - 24, color: PROMPT)
  end
end

game = RGame::Game.new(
  root: Room.new,
  caption: 'Collectables',
  width: WIDTH,
  height: HEIGHT,
  media_root: ASSETS,
  locales: LOCALES
)

game.start
