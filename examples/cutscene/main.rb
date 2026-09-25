# frozen_string_literal: true

# Cutscene — a scene everybody watches, and a skip that ends it the same way.
#
# Run it:
#
#   ruby examples/cutscene/main.rb
#
# Arrow keys, WASD, a d-pad or a left stick walk a hero. Press A on a
# controller and a second player joins. Player one presses E to hear the town
# crier: the screen becomes one view, the crier walks to the square, speaks, and
# waits for Return or Space. Holding Tab for 0.6 seconds skips it. It exercises:
#   - Engine::Cutscene::Script — the steps, as a constant a class holds;
#   - Components::Cutscene — the runner, which takes the window, the joins and
#     the heroes, and gives them back;
#   - Components::PathFollow — the crier's walk, which a `hold` waits on and a
#     skip finishes;
#   - UI::DialogueBox — the crier's words, which a `talk` waits on and a skip
#     ends where they stand;
#   - Viewports#solo! — the one view the cutscene shows, through its own camera.
#
# ## A skip ends in the same world
#
# Every step says how it is skipped. The walk is finished, so the crier stands
# at the square. The conversation ends where it stands. The last step, which
# opens the gate, runs. So a player who skipped and a player who watched see the
# same town afterwards: the crier in the square, the gate open, and the screen
# split again.
#
# The gate opens in a `run` after the conversation rather than in a response,
# because a skipped conversation picks no response.
#
# ## Nothing in the script puts anything back
#
# The cutscene suspends both heroes, solos the window through its camera, and
# stops a third player joining. When it ends it gives each of them back itself,
# so no step of the script has to, and a script cut short leaves nothing
# stopped.
#
# ## What this does not solve
#
# The cutscene plays once. Only player one starts or skips it, since it reads
# the player its node answers to. The crier walks through walls: a walk placed
# on a path ignores the map, and a crier that should go round them plans its
# route with a `Navigator`.

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

WIDTH  = 640
HEIGHT = 480
ASSETS = File.expand_path('../assets', __dir__)
LOCALES = File.expand_path('locales', __dir__) # the text on screen: locales/en.yml

SPEED = 80.0 # px/s

# Where the heroes start on town.tmx, one per seat.
STARTS = [[376, 262], [424, 262]].freeze

# A player's hero: `examples/walk`'s hero, with a camera on it.
class Hero < RGame::Engine::Node2D
  def initialize(camera:, **)
    super(**)
    add_component(RGame::Engine::Components::AnimatedSprite.new(sheet: 'hero.json'))
    add_component(RGame::Engine::Components::FeetCollider.new(width: 12, height: 6))
    add_component(RGame::Engine::Components::CharacterBody.new(speed: SPEED, blocked_by: [:tiles]))
    add_component(RGame::Engine::Components::PlayerController.new)
    add_component(RGame::Engine::Components::CameraFollow.new(camera: camera))
  end
end

# The crier: a hero's sprite with a bell over it, walked along a path, and
# followed by the cutscene's camera.
class Crier < RGame::Engine::Node2D
  BELL = RGame::Util::Color.new(236, 196, 64)
  ROUTE = RGame::Engine::Path.new([[552.0, 128.0], [552.0, 232.0], [456.0, 232.0]])

  attr_reader :walk

  def initialize(camera:)
    super(x: 552, y: 128)
    add_component(RGame::Engine::Components::AnimatedSprite.new(sheet: 'hero.json'))
    add_component(RGame::Engine::Components::CameraFollow.new(camera: camera))
    @walk = add_component(RGame::Engine::Components::PathFollow.new(speed: 40.0))
  end

  # Walks to the square, and hands the walk to the step that waits on it.
  def walk_to_square = @walk.tap { it.follow(ROUTE) }

  def _draw(renderer, _view) = renderer.rect(-3, -30, 6, 6, color: BELL)
end

# The gate to the garden, on the square town.tmx keeps for it. It draws while
# it is shut.
class Gate < RGame::Engine::Node2D
  COLOR = RGame::Util::Color.new(150, 104, 56)

  attr_accessor :open

  def initialize
    super(x: 544, y: 80, width: 16, height: 16)
    @open = false
  end

  def _draw(renderer, _view)
    renderer.rect(0, 0, width, height, color: COLOR) unless @open
  end
end

# The town: the map, the heroes, the crier and the gate, and the cutscene that
# ties them together. It draws the help and the gate's state over everything.
class Town < RGame::Engine::Node2D
  CRIER = RGame::Engine::Dialogue::Script.build(start: :news, scope: 'crier') do
    beat :news, speaker: :crier, line: 'news', to: :gate
    beat :gate, speaker: :crier, line: 'gate'
  end

  NEWS = RGame::Engine::Cutscene::Script.build do
    wait 0.5
    hold(&:walk_crier)
    talk { it.say(CRIER) }
    press
    run(&:open_gate)
  end

  STATE = {
    shut: RGame::Engine::Text.new('gate.shut'),
    open: RGame::Engine::Text.new('gate.open')
  }.freeze

  def initialize
    super(band: :overlay)
    @help = RGame::Engine::Text.new('help.keys')
    @heroes = []
    @camera = RGame::Engine::Camera.new
  end

  def _enter_tree
    map = root.context.assets.tilemap('town.tmx').map
    world = add_component(RGame::Engine::Components::TileWorld.new(map:, tilemap_id: 'town.tmx'))
    add_component(RGame::Engine::Components::CollisionWorld.new(cell_size: 32))
    @actors = RGame::Engine::TileMapLayer.mount(add_node(RGame::Engine::WorldView.new),
                                                gaps: { actors: nil })[:actors]
    @gate = @actors.add_node(Gate.new)
    @crier = @actors.add_node(Crier.new(camera: @camera))
    players = system!(RGame::Engine::Players)
    players.each { world.bound(it.camera) }
    world.bound(@camera)
    players.each_active { spawn(it) }
    players.on_joined { spawn(it) }
  end

  # hot-path
  def _control(actions)
    return unless @cutscene.nil? && actions.pressed?(:interact)

    @cutscene = add_component(RGame::Engine::Components::Cutscene.new(
                                NEWS, context: self, camera: @camera, pause: @heroes, skip: :skip
                              ))
  end

  def _draw(renderer, view)
    renderer.text(@help, 12, view.height - 30)
    renderer.text(@gate.open ? STATE[:open] : STATE[:shut], 12, 12)
  end

  # Walks the crier to the square, and hands the walk to the step that waits
  # on it.
  def walk_crier = @crier.walk_to_square

  # Puts the crier's words up, and hands their dialogue to the step that waits
  # on it.
  def say(script)
    dialogue = RGame::Engine::Dialogue.new(script)
    add_node(RGame::Engine::UI::DialogueBox.new(dialogue:, unavailable: :hide, width: 480, reveal: nil, x: 80,
                                                y: 330))
    dialogue
  end

  def open_gate = @gate.open = true

  private

  def spawn(player)
    x, y = STARTS.fetch(player.id)
    hero = Hero.new(camera: player.camera, x:, y:)
    hero.input_owner = player
    @heroes << hero
    @actors.add_node(hero)
  end
end

game = RGame::Game.new(
  root: Town.new,
  caption: 'Cutscene',
  width: WIDTH,
  height: HEIGHT,
  media_root: ASSETS,
  locales: LOCALES,
  players: 2,
  input_map: RGame::Engine::InputMap.default.merge(
    # Held, so a stray press does not throw the scene away.
    skip: { buttons: [RGame::Util::Controls::KEY_TAB, RGame::Util::Controls::PAD_Y], hold: 0.6 }
  )
)

game.start
