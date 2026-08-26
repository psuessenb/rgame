# frozen_string_literal: true

class Snake < RGame::Engine::Node2D
  SIZE = 10

  def initialize
    super(width: SIZE, height: SIZE)
  end

  def on_add
    world = system(RGame::Engine::Components::WorldBounds)
    self.x = world.world_width / 2.0
    self.y = world.world_height / 2.0

    add_component(RGame::Engine::Components::CharacterBody.new(speed: 10))
    add_component(RGame::Engine::Components::PlayerController.new)
  end

  def on_draw(renderer, _view)
    renderer.rect(x, y, width, height)
  end
end
