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
    self.scene = self
    @collision_world = add_component(RGame::Engine::Components::CollisionWorld.new(cell_size:))
    @rng = Random.new
  end

  # Drawn in the grid's own space: (0, 0) is the grid's top-left corner
  # wherever the tree has put it.
  def on_draw(renderer, _view)
    renderer.line(0, 0, 0, height)
    renderer.line(width, height, width, 0)
    renderer.line(width, 0, 0, 0)
    renderer.line(0, height, width, height)
  end

  def on_board?(col, row)
    col.between?(0, @cols - 1) && row.between?(0, @rows - 1)
  end

  def random_free_space
    x = @rng.rand(@cols)
    y = @rng.rand(@rows)

    if @collision_world.cell_empty?(x, y)
      [x, y]
    else
      random_free_space
    end
  end

  def cell_size
    CELL_SIZE
  end
end

class SnakePart < RGame::Engine::Node2D
  attr_accessor :next
  attr_reader :cell_x, :cell_y

  signal :on_destroyed

  def initialize(cell_x:, cell_y:, cell_size:, previous: nil)
    super(width: cell_size, height: cell_size)
    @previous = previous
    @previous&.next = self
    @cell_size = cell_size
    place(cell_x, cell_y)

    collider = add_component(RGame::Engine::Components::BoxCollider.new(width:, height:, layer: :snake))
    collider.on_hit do |other|
      on_destroyed_signal.emit if other.layer == :snake
    end
  end

  def on_draw(renderer, _view)
    renderer.rect(0, 0, width - 1, height - 1, color: RGame::Util::Color::GREEN)
  end

  # Recycle this part as the snake's new head: move it onto `cell_x, cell_y` and link
  # it behind the part that was the head until now. Returns self, so the caller can
  # write `@head = @tail.attach(...)`.
  def attach(cell_x:, cell_y:, previous:)
    place(cell_x, cell_y)
    @previous = previous
    previous.next = self
    self
  end

  private

  # Board square and pixel position are set together, never one without the other:
  # Snake#move works out the next square from the head's, so a part whose cell_x has
  # drifted from its x stops the whole snake.
  def place(cell_x, cell_y)
    @cell_x = cell_x
    @cell_y = cell_y
    self.x = cell_x * @cell_size
    self.y = cell_y * @cell_size
  end
end

class Snake < RGame::Engine::Node2D
  START_LENGTH = 6
  MOVE_SPEED = 0.1

  signal :on_destroyed

  def initialize(cell_x:, cell_y:, cell_size:)
    super()
    @cell_x = cell_x
    @cell_y = cell_y
    @cell_size = cell_size
    @max_size = START_LENGTH
    @current_size = @max_size
  end

  def on_add
    @moved = 0.0
    move_intent(0, 1)
    build_body
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
    return if @dead

    @moved += dt
    return unless @moved >= MOVE_SPEED

    move
    @moved = 0.0
  end

  def grow
    @max_size += 1
  end

  private

  def move_intent(x, y)
    @intent_x = x
    @intent_y = y
  end

  def build_body
    previous = nil
    START_LENGTH.times do |i|
      behind = START_LENGTH - 1 - i
      previous = add_node(add_snake_part(
                            cell_x: @cell_x - (@intent_x * behind),
                            cell_y: @cell_y - (@intent_y * behind),
                            previous: previous
                          ))
      @tail ||= previous
    end
    @head = previous
  end

  def add_snake_part(cell_x:, cell_y:, previous:)
    snake_part = SnakePart.new(cell_x: cell_x, cell_y: cell_y, cell_size: @cell_size, previous: previous)
    snake_part.on_destroyed { die }
    snake_part
  end

  def die
    return if @dead

    @dead = true
    on_destroyed_signal.emit
  end

  def move
    next_x = @head.cell_x + @intent_x
    next_y = @head.cell_y + @intent_y

    return die unless parent.on_board?(next_x, next_y)

    if @current_size == @max_size
      new_head = @tail
      @tail = @tail.next
      @head = new_head.attach(cell_x: next_x, cell_y: next_y, previous: @head)
    else
      @head = add_node(
        add_snake_part(cell_x: next_x, cell_y: next_y, previous: @head)
      )
      @current_size += 1
    end
  end
end

class Fruit < RGame::Engine::Node2D
  attr_reader :cell_x, :cell_y

  def initialize(cell_size:)
    super(width: cell_size, height: cell_size)
    collider = add_component(RGame::Engine::Components::BoxCollider.new(width:, height:))
    collider.on_hit do |snake_part|
      snake_part.node.parent.grow
      spawn
    end
  end

  def on_draw(renderer, _view)
    renderer.rect(0, 0, width - 1, height - 1, color: RGame::Util::Color::RED)
  end

  def on_add
    spawn
  end

  def spawn
    @cell_x, @cell_y = parent.random_free_space
    self.x = @cell_x * width
    self.y = @cell_y * height
  end
end

class Root < RGame::Engine::Node2D
  def initialize
    super
    @grid = add_node(Grid.new(cols: 20, rows: 20))
    @grid.add_node(Fruit.new(cell_size: @grid.cell_size))
    @snake = Snake.new(cell_x: 10, cell_y: 10, cell_size: @grid.cell_size)
    @snake.on_destroyed { lose }
    @grid.add_node(@snake)
  end

  def lose
    @grid.paused = true
  end
end

game = RGame::Game.new(
  root: Root.new,
  caption: 'Snake',
  width: 800,
  height: 600
)

game.start
