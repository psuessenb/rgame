# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'
require_relative 'snake'

WIDTH  = 640
HEIGHT = 480

class Root < RGame::Engine::Node2D
  def on_add
    add_component(RGame::Engine::Components::World.new(width: context.width, height: context.height))

    @snake = add_node(Snake.new)
  end
end

game = RGame::Game.new(
  root: Root.new,
  caption: 'Example - Snake',
  width: WIDTH,
  height: HEIGHT
)

game.start
