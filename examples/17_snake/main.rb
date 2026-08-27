# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

class Grid < RGame::Engine::Node2D
  CELL_SIZE = 25

  attr_reader :cols, :rows

  def initialize(rows:, cols:)
    super(x: 150, y: 50)
    @rows = rows
    @cols = cols
    self.width = cols * CELL_SIZE
    self.height = rows * CELL_SIZE
  end

  def on_draw(renderer, _view)
    renderer.line(abs_x, abs_y, abs_x, abs_y + height)
    renderer.line(abs_x + width, abs_y + height, abs_x + width, abs_y)
    renderer.line(abs_x + width, abs_y, abs_x, abs_y)
    renderer.line(abs_x, abs_y + height, abs_x + width, abs_y + height)
  end

  def cell_size
    CELL_SIZE
  end

  def random_free_space
    [5, 5]
  end
end

class Snake < RGame::Engine::Node2D
  START_LENGTH = 6
  MOVE_SPEED = 0.1
  START_PARTS = (1...Snake::START_LENGTH)
  CELL_SIZE = 25

  def on_add
    world = system(RGame::Engine::Components::WorldBounds)
    x = (world.world_width / 2.0 / CELL_SIZE).round * CELL_SIZE
    y = (world.world_height / 2.0 / CELL_SIZE).round * CELL_SIZE
    @tail = add_node(SnakePart.new(x:, y:))
    previous = @tail
    START_PARTS.each do
      previous = add_node(SnakePart.new(x:, y:, previous:))
    end
    @head = previous
    @moved = 0.0
    move_intent(0, 1)
  end

  def on_control(actions)
    if actions.axis(:move_x).positive?
      move_intent(1, 0)
    elsif actions.axis(:move_x).negative?
      move_intent(-1, 0)
    elsif actions.axis(:move_y).positive?
      move_intent(0, 1)
    elsif actions.axis(:move_y).negative?
      move_intent(0, -1)
    end
  end

  def on_update(dt)
    @moved += dt
    return unless @moved >= MOVE_SPEED

    move
    @moved = 0.0
  end

  private

  def move_intent(x, y)
    @intent_x = x
    @intent_y = y
  end

  def move
    x = @head.x + @intent_x * CELL_SIZE
    y = @head.y + @intent_y * CELL_SIZE

    nil unless @current_size == @max_size

    new_head = @tail
    @tail = @tail.next
    @head = new_head.attach(x:, y:, previous: @head)
  end
end

class SnakePart < RGame::Engine::Node2D
  attr_accessor :next

  def initialize(x:, y:, previous: nil)
    super(x:, y:)
    @previous = previous
    @previous&.next = self
    add_component(RGame::Engine::Components::CharacterBody.new(speed: 0))
  end

  def on_draw(renderer, _view)
    renderer.rect(abs_x, abs_y, Snake::CELL_SIZE, Snake::CELL_SIZE, color: RGame::Util::Color::GREEN)
  end

  def attach(x:, y:, previous:)
    self.x = x
    self.y = y
    @previous = previous
    previous.next = self
  end
end

class Fruit < RGame::Engine::Node2D
  attr_reader :cell_x, :cell_y

  def on_draw(renderer, _view)
    renderer.rect(abs_x, abs_y, width, height, color: RGame::Util::Color::RED)
  end

  def on_add
    spawn
    self.width = parent.cell_size
    self.height = parent.cell_size
  end

  def spawn
    cell_x, cell_y = parent.random_free_space
    @cell_x = cell_x
    @cell_y = cell_y
    self.x = @cell_x * parent.cell_size
    self.y = @cell_y * parent.cell_size
  end
end

class Root < RGame::Engine::Node2D
  def initialize
    super
    @grid = add_node(Grid.new(cols: 20, rows: 20))
    @grid.add_node(Fruit.new)
  end
end

game = RGame::Game.new(
  root: Root.new,
  caption: 'Example - Snake',
  width: 800,
  height: 600
)

game.start
