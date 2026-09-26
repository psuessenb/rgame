# frozen_string_literal: true

# Block puzzle — push each block onto a marked square, one cell at a time.
#
# Run it:
#
#   ruby examples/block_puzzle/main.rb
#
# Arrow keys, WASD, a d-pad or a left stick walk. Walk into a block and keep
# pushing: after a moment it slides one cell, if the cell beyond is free. A tree
# or another block beyond it refuses the push. It exercises:
#   - Components::OccupiesCell — a block makes its cell of the map solid, so the
#     hero stops at it as at a tree;
#   - Components::Tween — the slide from one cell to the next;
#   - Components::CharacterBody — `on_blocked` and `on_unblocked`, which time the
#     push;
#   - Components::TileWorld — `solid?`, which decides whether the push is refused;
#   - Engine::Text — the count of blocks home.
#
# ## A block on a grid is not a Pushable
#
# `examples/push_pull` moves crates freely, pixel by pixel, with `pushes:` and
# `Components::Pushable`. A block puzzle wants the opposite: a block is always
# on a cell, moves a whole cell or not at all, and a half-pushed block is a bug.
# So a block here is a solid cell of the map. The hero's CharacterBody stops at
# it with `blocked_by: [:tiles]`, and nothing in the collision code knows blocks
# exist.
#
# The push is the game's rule, written against three things the engine already
# has. `on_blocked` says the hero started pressing into something, and
# `on_unblocked` says they stopped. Pressing for PUSH_AFTER seconds shoves
# whatever block is in the next cell, and `TileWorld#solid?` says whether the
# cell beyond it is free. The block then swaps its OccupiesCell for one on the
# new cell and slides there with a Tween.
#
# ## What this does not solve
#
# There is no undo and no reset, so a block pushed into a corner stays there.
# The level is one room, and the squares the blocks go to are placed in code
# rather than read from the map's object layer.

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

# The example's own module. `Engine`, `Util`, `UI` and `Components` inside it
# stand for rgame's namespaces of the same names, and every name the example
# defines stays off the top level. docs/api/README.md says why, under "A game's
# own module".
module BlockPuzzleExample
  Engine = RGame::Engine
  Util = RGame::Util
  UI = Engine::UI
  Components = Engine::Components

  WIDTH  = 640
  HEIGHT = 480
  ASSETS = File.expand_path('../assets', __dir__)
  LOCALES = File.expand_path('locales', __dir__)

  Color = Util::Color

  MAP = 'puzzle.tmx'

  HERO_SIZE = 12
  HERO_SPEED = 60.0

  BLOCK      = Color.new(170, 120, 70)
  BLOCK_HOME = Color.new(120, 170, 90)
  EDGE       = Color.new(60, 40, 24)
  SQUARE     = Color.new(250, 230, 140)
  HERO       = Color.new(90, 150, 230)
  HUD        = Color.new(240, 236, 224)
  HUD_BACK   = Color.new(20, 24, 20, 200)

  # A block: a solid cell of the map, and the slide between two of them.
  #
  # It is placed by cell and knows its cell. Its node position is drawn from the
  # slide's progress, so the block is solid on the new cell from the moment it is
  # shoved, and its picture catches up over SLIDE seconds.
  class Block < Engine::Node2D
    SLIDE = 0.15

    attr_reader :col, :row
    attr_writer :home

    def initialize(world:, col:, row:)
      super(x: world.cell_x(col), y: world.cell_y(row))
      @world = world
      @col = col
      @row = row
      @from_x = x
      @from_y = y
      @home = false
      add_component(Components::OccupiesCell.new(col:, row:))
      @slide = add_component(Components::Tween.new(SLIDE))
    end

    def at?(col, row) = @col == col && @row == row

    # Move one cell by (step_col, step_row), unless that cell is solid — a tree,
    # or a block already there.
    def shove(step_col, step_row)
      col = @col + step_col
      row = @row + step_row
      return if @world.solid?(col, row)

      remove_component(Components::OccupiesCell)
      add_component(Components::OccupiesCell.new(col:, row:))
      @col = col
      @row = row
      @from_x = x
      @from_y = y
      @slide.start
    end

    def _update(_dt)
      t = @slide.progress
      self.x = @from_x + ((@world.cell_x(@col) - @from_x) * t)
      self.y = @from_y + ((@world.cell_y(@row) - @from_y) * t)
    end

    def _draw(renderer, _view)
      renderer.rect(0, 0, 16, 16, color: EDGE)
      renderer.rect(2, 2, 12, 12, color: @home ? BLOCK_HOME : BLOCK)
    end
  end

  # A square a block belongs on. It only draws: whether a block is home is the
  # room's question, asked by cell. Its `z: -1` keeps it on the floor, under a block
  # sliding onto it.
  class Square < Engine::Node2D
    attr_reader :col, :row

    def initialize(world:, col:, row:)
      super(x: world.cell_x(col), y: world.cell_y(row), z: -1)
      @col = col
      @row = row
    end

    def _draw(renderer, _view)
      renderer.rect(0, 0, 16, 2, color: SQUARE)
      renderer.rect(0, 14, 16, 2, color: SQUARE)
      renderer.rect(0, 2, 2, 12, color: SQUARE)
      renderer.rect(14, 2, 2, 12, color: SQUARE)
    end
  end

  # The hero, and the rule that makes a press a push.
  #
  # `on_blocked` fires once, on the step the hero starts pressing into something,
  # with the axis it stopped. From then until `on_unblocked`, the hero is still
  # pressing, and every PUSH_AFTER seconds of it shoves the block in the cell
  # ahead, if there is one. A tree ahead is pressed against for nothing.
  class Hero < Engine::Node2D
    PUSH_AFTER = 0.2

    def initialize(room:, **)
      super(**)
      @room = room
      @pressing = nil
      @pressed_for = 0.0
      add_component(Components::BoxCollider.new(width: HERO_SIZE, height: HERO_SIZE,
                                                layer: :hero))
      @body = add_component(Components::CharacterBody.new(speed: HERO_SPEED,
                                                          blocked_by: [:tiles]))
      add_component(Components::PlayerController.new)
      @body.on_blocked { |_by, axis| press(axis) }
      @body.on_unblocked { @pressing = nil }
    end

    def _update(dt)
      return unless @pressing

      @pressed_for += dt
      return if @pressed_for < PUSH_AFTER

      @pressed_for = 0.0
      shove_ahead
    end

    def _draw(renderer, _view) = renderer.rect(0, 0, HERO_SIZE, HERO_SIZE, color: HERO)

    private

    def press(axis)
      @pressing = axis == :both ? nil : axis
      @pressed_for = 0.0
    end

    # The cell just past the hero's leading edge, in the direction it presses.
    def shove_ahead
      step_col = @pressing == :x ? (@body.heading_x <=> 0) : 0
      step_row = @pressing == :y ? (@body.heading_y <=> 0) : 0
      half = HERO_SIZE / 2.0
      ahead_x = world_x + half + (step_col * (half + 1))
      ahead_y = world_y + half + (step_row * (half + 1))
      @room.shove(ahead_x, ahead_y, step_col, step_row)
    end
  end

  # The help line and the count, in the `:overlay` band so they draw over the map,
  # once across the window. A node draws in the `:world` band unless it says
  # otherwise, and the map is there.
  class Hud < Engine::Node2D
    def initialize(room:)
      super(band: :overlay)
      @room = room
      @help = Engine::Text.new('help.walk')
      @count = Engine::Text.new('hud.home', :home, :total)
      @solved = Engine::Text.new('hud.solved')
    end

    def _draw(renderer, view)
      home = @room.home
      total = @room.total
      renderer.rect(0, 0, view.width, 60, color: HUD_BACK)
      renderer.text(@help, 12, 10, color: HUD)
      renderer.text(home == total ? @solved : @count.with(home:, total:), 12, 34, color: HUD)
    end
  end

  # The room: the map, the blocks and their squares, the hero, and the count.
  class Room < Engine::Node2D
    BLOCKS = [[16, 12], [15, 15]].freeze
    SQUARES = [[22, 12], [17, 18]].freeze
    START = [13, 12].freeze

    def _enter_tree
      map = root.context.assets.tilemap(MAP).map
      players = root.system(Engine::Players)
      @world = add_component(Components::TileWorld.new(
                               map: map, tilemap_id: MAP, cameras: players.map(&:camera)
                             ))

      view = add_node(Engine::WorldView.new)
      actors = Engine::TileMapLayer.mount(view)[:actors]
      @squares = SQUARES.map { |col, row| actors.add_node(Square.new(world: @world, col:, row:)) }
      @blocks = BLOCKS.map { |col, row| actors.add_node(Block.new(world: @world, col:, row:)) }
      actors.add_node(Hero.new(room: self, x: @world.cell_x(START.first) + 2, y: @world.cell_y(START.last) + 2))
      @home = 0
      add_node(Hud.new(room: self))
    end

    # How many blocks stand on a square, and how many there are.
    attr_reader :home

    def total = @blocks.size

    # Shove the block standing on the cell under (world_x, world_y), if any, one
    # cell by (step_col, step_row).
    def shove(world_x, world_y, step_col, step_row)
      col = @world.col_at(world_x)
      row = @world.row_at(world_y)
      block = @blocks.find { it.at?(col, row) }
      return unless block

      block.shove(step_col, step_row)
      count_home
    end

    private

    def count_home
      @home = 0
      @blocks.each do |block|
        home = @squares.any? { block.at?(it.col, it.row) }
        block.home = home
        @home += 1 if home
      end
    end
  end

  # Builds the game and runs it until the window closes.
  def self.start
    game = RGame::Game.new(
      root: Room.new,
      caption: 'Block puzzle',
      width: WIDTH,
      height: HEIGHT,
      media_root: ASSETS,
      locales: LOCALES
    )

    game.start
  end
end

BlockPuzzleExample.start
