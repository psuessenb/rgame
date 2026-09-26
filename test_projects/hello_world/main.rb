# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

module HelloWorld
  Engine = RGame::Engine
  Util = RGame::Util

  class Scene < Engine::Node2D
    def _draw(renderer, _view)
      renderer.text('Hello world!', 250, 200)
    end
  end
end

game = RGame::Game.new(
  root: HelloWorld::Scene.new,
  caption: 'Hello world!'
)

game.start
