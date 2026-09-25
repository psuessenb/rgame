# frozen_string_literal: true

# A raft of Tiny Town planks, centred on its node, that walks its route for good:
# back and forth along a polyline, or round a polygon. Its box is the floor over
# the chasm, and its PathFollow is what carries its riders.
class Raft < RGame::Engine::Node2D
  TILES = 'tiles.json'
  TILE = 16
  PLANK_ROW = 6
  LEFT = 0
  MIDDLE = 1
  RIGHT = 3

  SPEED = 40.0

  def initialize(route:, width:, height:)
    super(x: route.x_at(0), y: route.y_at(0))
    add_component(RGame::Engine::Components::BoxCollider.new(
                    width: width, height: height, offset_x: -width / 2.0, offset_y: -height / 2.0
                  ))
    add_component(RGame::Engine::Components::Platform.new)
    add_component(RGame::Engine::Components::PathFollow.new(speed: SPEED, path: route, loop: true))
    @columns = width / TILE
    @rows = height / TILE
    @left = -width / 2.0
    @top = -height / 2.0
  end

  def _draw(renderer, _view)
    @rows.times do |row|
      @columns.times do |column|
        renderer.sprite(TILES, PLANK_ROW, plank(column), @left + (column * TILE), @top + (row * TILE))
      end
    end
  end

  private

  def plank(column)
    return LEFT if column.zero?

    column == @columns - 1 ? RIGHT : MIDDLE
  end
end
