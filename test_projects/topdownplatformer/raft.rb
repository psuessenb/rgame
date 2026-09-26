# frozen_string_literal: true

module TopDownPlatformer
  # A raft of Tiny Town planks, centred on its node, that walks its route for good:
  # back and forth along a polyline, or round a polygon. Its box is the floor over
  # the chasm, and its PathFollow is what carries its riders. The map builds it
  # from the route, and the node starts on the route's first point.
  class Raft < Engine::Node2D
    TILES = 'tiles.json'
    TILE = 16
    PLANK_ROW = 6
    LEFT = 0
    MIDDLE = 1
    RIGHT = 3

    SPEED = 40.0

    # @param deck_width [Integer] the raft's width in pixels, a multiple of 16
    # @param deck_height [Integer] its height in pixels, a multiple of 16
    def initialize(route:, deck_width:, deck_height:, **)
      super(**)
      add_component(Components::BoxCollider.new(
                      width: deck_width, height: deck_height, offset_x: -deck_width / 2.0, offset_y: -deck_height / 2.0
                    ))
      add_component(Components::Platform.new)
      add_component(Components::PathFollow.new(speed: SPEED, path: route, loop: true))
      @columns = deck_width / TILE
      @rows = deck_height / TILE
      @left = -deck_width / 2.0
      @top = -deck_height / 2.0
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
end
