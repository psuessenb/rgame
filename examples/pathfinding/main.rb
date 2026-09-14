# frozen_string_literal: true

# Pathfinding — pick a tile, and the hero works out how to get there.
#
# Run it:
#
#   ruby examples/pathfinding/main.rb
#
# The arrow keys or a d-pad move the tile cursor, and holding one keeps it moving.
# Return, Space or the pad's A button sends the hero there. The trees and the fence
# are solid, and the fence has one gap. It exercises:
#   - Components::Navigator — `go_to(world_x, world_y)`: a route over the map,
#     smoothed against the hero's own feet box, and walked;
#   - Components::TileWorld#nav_grid — the search grid, built from the same
#     solidity the collision uses, and asked whether a tile can be stood on;
#   - Components::AnimatedSprite — facing the way the route goes, with nobody
#     pressing a direction;
#   - Components::ActionTrigger — the cursor's held-key repeat;
#   - Components::CameraFollow — on the cursor rather than on the hero;
#   - Engine::CachedLabel — the route's size and state, built only when they change;
#   - the TileWorld, FeetCollider and TileMapLayer scene from `examples/collision_tiles`.
#
# ## Two drawings of one route
#
# The small dots are the route the search found: one per tile, start to target,
# each a step to a neighbouring tile. The lines are the route the hero walks. They
# are the same route, and the difference between them is the point of this file.
#
# A tile-by-tile route walked as it stands zig-zags. It turns wherever the grid
# does, which is at every tile a diagonal meets a straight, and a character doing
# that looks like it is being steered by a spreadsheet. So the navigator pulls the
# route tight: from each corner it keeps going straight for as long as it can, and
# turns only where it has to. Send the hero across open ground and there is one
# line; send it through the fence and there are a handful, against dozens of dots.
#
# ## "As long as it can" means as long as the feet fit
#
# A straight line is kept only if the hero's feet box — the red box in
# `examples/collision_tiles`, twelve by six — can travel it without touching a
# solid tile, and the thing asked is the same `TileWorld` that stops the hero when
# it walks. A line tested against tiles alone would cut past a tree's corner that a
# point clears and a feet box clips. The hero does not slide along the tree the way
# a player-steered character would: it is on a route, so it would stand at that
# corner pressing into it. The search and the collision cannot disagree about what
# fits, because they are asking one map.
#
# ## The cursor, and where the camera looks
#
# The camera follows the cursor, not the hero. A target is picked by looking at it,
# and a cursor that could be walked off the screen would be lost; the hero is the
# thing that is allowed to leave the view, and it walks back into it on its way to
# the tile you picked.
#
# The outline is green on a tile the hero can stand on and red on a solid one. That
# is read from the grid once each time the cursor moves, not every frame. Confirming
# on a red tile does nothing to the hero — there is no route to a tree, and the
# navigator says so by returning `false` — so a hero already walking carries on.
#
# ## What this scene does not solve
#
# The hero plans against the map and nothing else. Give it `blocked_by: %i[tiles
# npc]` and it waits behind a villager standing on its route rather than going
# round; a game that wants it to go round calls `go_to` again. The map never
# changes, so the grid is built once, the first time it is asked for — a door that
# opens would need a grid that is told. And there is one hero: many walkers heading
# for one place want a different search from many separate ones.

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

WIDTH  = 640
HEIGHT = 480
ASSETS = File.expand_path('../assets', __dir__)

MAP   = 'town.tmx'
TILE  = 16
SPEED = 90.0 # px/s

FEET_WIDTH  = 12
FEET_HEIGHT = 6

# The tile the hero starts on: north of the fence and well east of its gap, so any
# route south goes the long way.
START_COL = 24
START_ROW = 18

# The middle of the feet box, from the hero's origin: centred across the 16px-wide
# sprite, and half the box up from the bottom of its 22px height. Standing the hero
# with this point on a tile's centre is standing it on that tile.
FEET_CENTRE_X = 8
FEET_CENTRE_Y = 19

# How often a held direction moves the cursor another tile.
CURSOR_REPEAT = 0.12 # s

# A sprite, a feet box and a navigator. Where `examples/collision_tiles` has a
# CharacterBody and a PlayerController, this hero has one component that plans
# its own movement, and nothing reads the keyboard on its behalf.
class Hero < RGame::Engine::Node2D
  attr_reader :navigator, :collider

  def initialize(**)
    super
    add_component(RGame::Engine::Components::AnimatedSprite.new(sheet: 'hero.json'))
    @collider = add_component(RGame::Engine::Components::FeetCollider.new(
                                width: FEET_WIDTH, height: FEET_HEIGHT
                              ))
    @navigator = add_component(RGame::Engine::Components::Navigator.new(
                                 speed: SPEED, blocked_by: [:tiles]
                               ))
  end
end

# A tile outline, moved a tile at a time. It knows which tile it is on and whether
# that tile can be stood on; what confirming *means* is the scene's business, so it
# only reports the tile's centre.
class Cursor < RGame::Engine::Node2D
  WALKABLE = RGame::Util::Color.rgba(120, 230, 120, 255)
  SOLID = RGame::Util::Color.rgba(240, 90, 90, 255)
  STEPS = { ui_left: [-1, 0], ui_right: [1, 0], ui_up: [0, -1], ui_down: [0, 1] }.freeze

  signal :on_confirmed, RGame::Engine::Signal.define(:world_x, :world_y)

  def initialize(col:, row:, camera:)
    super(x: col * TILE, y: row * TILE)
    @col = col
    @row = row
    # ActionTrigger fires on the tick a direction goes down and again every
    # CURSOR_REPEAT while it stays down — which is a key repeat, per action.
    repeat = add_component(RGame::Engine::Components::ActionTrigger.new(
                             STEPS.keys.to_h { |action| [action, CURSOR_REPEAT] }
                           ))
    repeat.on_triggered { |action| step(*STEPS.fetch(action)) }
    add_component(RGame::Engine::Components::CameraFollow.new(
                    camera: camera, offset_x: TILE / 2, offset_y: TILE / 2
                  ))
  end

  def on_add
    @world = system(RGame::Engine::Components::TileWorld)
    step(0, 0)
  end

  def on_control(actions)
    return unless actions.pressed?(:ui_confirm)

    on_confirmed_signal.emit(world_x: (@col + 0.5) * TILE, world_y: (@row + 0.5) * TILE)
  end

  def on_draw(renderer, _view)
    renderer.line(0, 0, TILE, 0, thickness: 2.0, color: @color)
    renderer.line(TILE, 0, TILE, TILE, thickness: 2.0, color: @color)
    renderer.line(TILE, TILE, 0, TILE, thickness: 2.0, color: @color)
    renderer.line(0, TILE, 0, 0, thickness: 2.0, color: @color)
  end

  private

  def step(dcol, drow)
    grid = @world.nav_grid
    @col = (@col + dcol).clamp(0, grid.width - 1)
    @row = (@row + drow).clamp(0, grid.height - 1)
    self.x = @col * TILE
    self.y = @row * TILE
    @color = grid.walkable?(@col, @row) ? WALKABLE : SOLID
  end
end

# Both drawings of the hero's current route, in world space: a dot per tile the
# search returned, and a line per segment of the path being walked.
#
# The path's waypoints are where the hero's *origin* goes — its sprite's top-left
# corner — while the route was planned for the middle of its feet. Adding the feet
# box's centre back puts the lines on the ground the dots are on.
class Route < RGame::Engine::Node2D
  DOT = RGame::Util::Color.rgba(255, 255, 255, 200)
  LINE = RGame::Util::Color.rgba(255, 220, 60, 255)
  DOT_SIZE = 4

  def initialize(hero:)
    super()
    @hero = hero
  end

  def on_draw(renderer, _view)
    navigator = @hero.navigator
    draw_cells(renderer, navigator.cells) if navigator.cells
    draw_path(renderer, navigator.path) if navigator.path
  end

  private

  def draw_cells(renderer, cells)
    offset = (TILE - DOT_SIZE) / 2
    index = 0
    while index < cells.length
      col, row = cells[index]
      renderer.rect((col * TILE) + offset, (row * TILE) + offset, DOT_SIZE, DOT_SIZE, color: DOT)
      index += 1
    end
  end

  def draw_path(renderer, path)
    box = @hero.collider.box
    feet_x = box.offset_x + (box.width / 2.0)
    feet_y = box.offset_y + (box.height / 2.0)
    index = 1
    while index < path.count
      renderer.line(path.x_at(index - 1) + feet_x, path.y_at(index - 1) + feet_y,
                    path.x_at(index) + feet_x, path.y_at(index) + feet_y,
                    thickness: 2.0, color: LINE)
      index += 1
    end
  end
end

# The scene: the map and its world, the hero, the route drawn under the hero and
# the cursor over it — and the one line that connects a confirmed tile to a walk.
class Scene < RGame::Engine::Node2D
  # What the status line reads before anything has been asked for.
  IDLE = 'Move the cursor to a tile and confirm'

  def on_add
    map = root.context.assets.tilemap(MAP).map
    players = root.system(RGame::Engine::Players)
    add_component(RGame::Engine::Components::TileWorld.new(
                    map: map, tilemap_id: MAP, cameras: players.map(&:camera)
                  ))

    view = add_node(RGame::Engine::WorldView.new)
    actors = RGame::Engine::TileMapLayer.mount(view)
    @hero = Hero.new(x: ((START_COL + 0.5) * TILE) - FEET_CENTRE_X,
                     y: ((START_ROW + 0.5) * TILE) - FEET_CENTRE_Y)
    actors.add_node(Route.new(hero: @hero))
    actors.add_node(@hero)
    cursor = actors.add_node(Cursor.new(col: START_COL, row: START_ROW, camera: players.primary.camera))

    cursor.on_confirmed { |world_x, world_y| send_hero(world_x, world_y) }
    @hero.navigator.on_finished do
      @arrived = true
      report
    end

    @arrived = false
    @status = nil
    @status_label = RGame::Engine::CachedLabel.new { |status| describe(status) }
  end

  def on_draw(renderer, _view)
    renderer.text('Arrows / d-pad move the cursor; Return / Space / A sends the hero', 12, 12)
    renderer.text('Dots: the route the search found. Lines: the route the hero walks', 12, 34)
    renderer.text(@status_label[@status], 12, 56)
  end

  private

  def send_hero(world_x, world_y)
    routed = @hero.navigator.go_to(world_x, world_y)
    @arrived = false if routed
    report(refused: !routed)
  end

  # The status is rebuilt on an event, never per frame, so the label's value only
  # changes when there is something new to say.
  def report(refused: false)
    navigator = @hero.navigator
    @status = [navigator.cells&.length, navigator.path&.count, @arrived, refused].freeze
  end

  def describe(status)
    return IDLE unless status

    cells, waypoints, arrived, refused = status
    route = cells && "#{arrived ? 'arrived' : 'walking'}: #{waypoints} waypoints, #{cells} cells"
    return route unless refused

    route ? "no route there; #{route}" : 'no route there'
  end
end

game = RGame::Game.new(
  root: Scene.new,
  caption: 'Pathfinding',
  width: WIDTH,
  height: HEIGHT,
  media_root: ASSETS
)

game.start
