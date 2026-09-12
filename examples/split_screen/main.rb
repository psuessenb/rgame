# frozen_string_literal: true

# Split screen — two players, one world.
#
# Run it:
#
#   ruby examples/split_screen/main.rb
#
# Player one walks with the arrow keys or WASD. Press **A** on a controller and
# player two joins: the screen splits, a second walker appears, and each half
# follows its own player. Space (or A) waves, and only the waver's own badge
# counts it. It exercises:
#   - Game.new(players: 2) — two seats, the second of them empty at the start;
#   - Engine::Players — who is playing, and the `on_joined` signal that says
#     somebody now is;
#   - Engine::WorldView — the world, drawn once per viewport through that
#     viewport's camera;
#   - Engine::PlayerLayer — one player's own corner of the screen;
#   - Engine::Camera and Components::CameraFollow — one camera per player;
#   - `input_owner` — which player a subtree answers to, inherited like a
#     transform.
#
# ## The world does not know how many times it is drawn
#
# That is the sentence the whole design exists to make true, and this example is
# the only place it can be shown rather than asserted. `Ground` draws the floor
# once in its `on_draw`; with two players that method runs twice a frame, with
# one it runs once, and nothing in it can tell. The walkers are the same: each is
# a node in the world, so each is drawn in every viewport that can see it —
# player two walks around inside player one's view, because there is one world
# and two windows onto it.
#
# The update is not doubled. A frame is one `update(dt)` over the whole tree and
# then one `draw` per viewport, so nothing moves twice when the screen splits.
#
# ## What a viewport cannot see, it does not draw
#
# The two walkers start side by side and each appears in both halves. Walk them
# apart and each half is down to one sprite, because `AnimatedSprite` compares
# the node's world box against the view's camera rectangle and skips the draw —
# `Engine::Culling`, which split-screen is the reason for: with one viewport a
# skipped draw saved a little, and with one per player it saves that much per
# player.
#
# Only components that know a node's footprint cull. The banner `Walker` draws
# itself is not culled, just clipped away with the rest of what is outside the
# region — at one rectangle a check would cost more than the draw, and that is
# the trade rather than an oversight.
#
# ## Three kinds of content, and a node's place decides which it is
#
# A frame here holds all three, and no node is told which it is in:
#
#   - **world content** — under the `WorldView`, drawn once per viewport, through
#     that viewport's camera, so its coordinates are places in the world;
#   - **a player's own screen space** — under a `PlayerLayer`, drawn once for that
#     player, clipped to their region and laid out from *its* corner, so a badge
#     at (16, 16) is sixteen pixels inside whichever half they were given;
#   - **a global overlay** — a plain child of the scene, like the two lines of
#     instructions at the bottom. Drawn once across the whole window whatever the
#     split is doing.
#
# ## The screen splits when somebody joins, not when a pad is plugged in
#
# The game opens with two seats and one player. The second seat is empty, so
# there is one viewport and it is the whole window — an ordinary single-player
# game, which is what a two-player game should look like until the second player
# turns up.
#
# A device is seated when somebody *uses* it. Pressing A on an unassigned
# controller fills the empty seat, `Players#on_joined` fires with the player who
# got it, and this scene spawns their walker and their badge in the handler. The
# split follows from there: `Viewports` gives a region to each active player, and
# one more active player is one more region. Nothing here counts anything or
# asks how the screen is divided.
#
# ## Ownership is inherited, so neither subtree mentions players
#
# `walker.input_owner = player` is the only line about ownership in this file,
# and `PlayerLayer` sets the same thing for its subtree. Everything below either
# one reads that player's device: `PlayerController` moves the right walker,
# `Badge#on_control` counts the right waves, and neither class names a player or
# knows that there is more than one.
#
# That is what keeps a HUD written for one player working for two. The badge
# under player two's layer is the same class, with nothing configured, drawn in
# their half because their layer is where it hangs.
#
# ## What it does not solve
#
# Anything about the world itself — there is a floor, some landmarks and two
# walkers, and they pass through each other. Every other example puts its subject
# in the world; this one's subject is the plumbing around it, and a busier world
# would only hide the thing being shown.
#
# `Ground` also draws the whole floor every time, which is thirty-eight
# rectangles and not worth thinking about. A world big enough for that to matter
# draws what the `view` it is handed can actually show — the same camera
# rectangle the sprites are culled against.

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

WIDTH  = 640
HEIGHT = 480
ASSETS = File.expand_path('../assets', __dir__)

# Bigger than the window on both axes, so a camera has somewhere to go and the
# two halves can be looking at genuinely different places.
WORLD_W = 1280
WORLD_H = 960

SPEED = 120.0

# Where the camera looks: the middle of the 16x22 sprite rather than its
# top-left origin.
CAMERA_OFFSET_X = 8
CAMERA_OFFSET_Y = 11

# One player, one colour. Their walker carries it as a banner and their badge
# prints their name in it, which is the only way to tell two halves apart at a
# glance.
TINTS = [RGame::Util::Color.new(255, 190, 90), RGame::Util::Color.new(120, 200, 255)].freeze

# Where each player's walker starts: side by side, so each of them is in the
# other's half of the screen until the two of them walk apart.
STARTS = [[520.0, 460.0], [700.0, 500.0]].freeze

# The world: a floor, a grid to make movement visible, and landmarks to tell one
# part of it from another. It is a single node under the WorldView, so this
# `on_draw` runs once per viewport and knows nothing about that.
class Ground < RGame::Engine::Node2D
  FLOOR = RGame::Util::Color.new(38, 54, 44)
  GRID  = RGame::Util::Color.new(50, 70, 58)
  CELL  = 64

  # x, y and a colour: four blocks in four quarters of the world, so which half
  # of the screen is looking where is obvious.
  LANDMARKS = [
    [200, 200, RGame::Util::Color.new(196, 92, 72)],
    [980, 240, RGame::Util::Color.new(92, 148, 196)],
    [260, 700, RGame::Util::Color.new(214, 196, 96)],
    [1000, 740, RGame::Util::Color.new(140, 110, 196)]
  ].freeze
  BLOCK = 64

  def on_draw(renderer, _view)
    renderer.rect(0, 0, WORLD_W, WORLD_H, color: FLOOR)
    draw_grid(renderer)
    LANDMARKS.each { |x, y, color| renderer.rect(x, y, BLOCK, BLOCK, color: color) }
  end

  private

  # While loops rather than ranges: this runs once per viewport per frame, and a
  # fresh Range every time is the allocation the hot-path cops refuse.
  #
  # hot-path
  def draw_grid(renderer)
    x = CELL
    while x < WORLD_W
      renderer.rect(x, 0, 1, WORLD_H, color: GRID)
      x += CELL
    end

    y = CELL
    while y < WORLD_H
      renderer.rect(0, y, WORLD_W, 1, color: GRID)
      y += CELL
    end
  end
end

# A player's avatar: `examples/walk`'s hero with a camera on it and a banner in
# their colour. Nothing in it refers to a player — the scene sets `input_owner`
# once, and the controller below reads whatever that resolves to.
class Walker < RGame::Engine::Node2D
  BANNER_H = 4

  def initialize(tint:, camera:, **)
    super(**)
    @tint = tint
    add_component(RGame::Engine::Components::AnimatedSprite.new(sheet: 'hero.json'))
    add_component(RGame::Engine::Components::CharacterBody.new(speed: SPEED))
    add_component(RGame::Engine::Components::PlayerController.new)
    add_component(RGame::Engine::Components::CameraFollow.new(
                    camera: camera, offset_x: CAMERA_OFFSET_X, offset_y: CAMERA_OFFSET_Y
                  ))
  end

  # Keep them on the floor. A plain CharacterBody walks wherever the intent
  # points; the cameras stop at the world's edges on their own, and a walker that
  # kept going would leave its half of the screen showing a player pushing a key
  # with nothing happening.
  def on_update(_dt)
    self.x = x.clamp(0, WORLD_W - width)
    self.y = y.clamp(0, WORLD_H - height)
  end

  def on_draw(renderer, _view) = renderer.rect(0, -BANNER_H - 2, width, BANNER_H, color: @tint)
end

# One player's badge, in their own corner of the screen.
#
# Written as though there were one player, because from in here there is. It
# hangs under a PlayerLayer, so it is drawn inside that player's region, laid out
# from that region's corner, and `on_control` is handed that player's actions.
class Badge < RGame::Engine::Node2D
  PANEL = RGame::Util::Color.new(20, 26, 34, 190)
  INK   = RGame::Util::Color.new(226, 230, 238)
  W = 108
  H = 46

  def initialize(name:, tint:, **)
    super(**)
    @name = name
    @tint = tint
    @waves = 0
    @label = RGame::Engine::CachedLabel.new { |count| "waves: #{count}" }
  end

  def on_control(actions)
    @waves += 1 if actions.pressed?(:fire)
  end

  def on_draw(renderer, _view)
    renderer.rect(0, 0, W, H, color: PANEL)
    renderer.rect(0, 0, W, 3, color: @tint)
    renderer.text(@name, 8, 8, color: @tint)
    renderer.text(@label[@waves], 8, 26, color: INK)
  end
end

class Scene < RGame::Engine::Node2D
  MARGIN = 16

  # Built once each, because a name that cannot change is not a label to
  # rebuild — the same reason `examples/save_load_ids` keeps its `id.to_s`.
  NAMES = ['Player 1', 'Player 2'].freeze

  def on_add
    @players = root.system(RGame::Engine::Players)
    # Every camera, including the empty seat's: a camera that does not know how
    # big the world is will happily show the void past its edge, and the seat is
    # filled later by somebody who should not have to remember this.
    @players.each { |player| bound(player.camera) }

    # World space begins here. Everything under it is drawn once per viewport,
    # through that viewport's camera.
    @view = add_node(RGame::Engine::WorldView.new)
    @view.add_node(Ground.new)

    # One walker and one badge per player who is already playing, and one more
    # when somebody joins. The scene never asks whether anybody has — the
    # registry tells it.
    @players.each_active { |player| spawn(player) }
    @players.on_joined { |player| spawn(player) }
  end

  # A plain child of the scene, so this is the global overlay: once across the
  # whole window, wherever the split is.
  def on_draw(renderer, view)
    renderer.text('Player one: arrows or WASD. Space waves', MARGIN, view.height - 52)
    renderer.text('Press A on a controller to join player two', MARGIN, view.height - 30)
  end

  private

  def bound(camera)
    camera.world_width = WORLD_W
    camera.world_height = WORLD_H
  end

  def spawn(player)
    x, y = STARTS[player.id]
    walker = Walker.new(x: x, y: y, tint: TINTS[player.id], camera: player.camera)
    # The only line in this file about who owns what. It is inherited by the
    # whole subtree, which is why nothing under it needs telling.
    walker.input_owner = player
    @view.add_node(walker)

    layer = add_node(RGame::Engine::PlayerLayer.new(player: player))
    layer.add_node(Badge.new(name: NAMES[player.id], tint: TINTS[player.id],
                             x: MARGIN, y: MARGIN))
  end
end

game = RGame::Game.new(
  root: Scene.new,
  caption: 'Split screen',
  width: WIDTH,
  height: HEIGHT,
  media_root: ASSETS,
  # Two seats. The second stays empty until somebody picks up a controller and
  # presses confirm, and until then this is an ordinary one-player game.
  players: 2
)

game.start
