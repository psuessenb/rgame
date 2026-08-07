# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

class Scene < RGame::Engine::Node2D
  def on_draw(renderer)
    renderer.text('Hello world!', 250, 200)
  end
end

game = RGame::Game.new(
  root: Scene.new,
  caption: 'Hello world!'
)

game.start
