# frozen_string_literal: true

# A coin either hero picks up by walking over it.
#
# `by: :hero` is the layer both heroes' feet boxes are on, so whoever gets there
# first takes it and the other finds nothing — which is the split-screen case
# worth having in a project: one shared world, two people in it.
class Coin < RGame::Engine::Node2D
  RADIUS = 6
  COLOR = RGame::Util::Color.new(240, 200, 96)

  def initialize(**)
    super
    add_component(RGame::Engine::Components::CircleCollider.new(radius: RADIUS, layer: :pickup))
    add_component(RGame::Engine::Components::Collectable.new(by: :hero, sound: 'blip.ogg'))
  end

  def collectable = get_component(RGame::Engine::Components::Collectable)

  def _draw(renderer, _view) = renderer.circle(0, 0, RADIUS, color: COLOR)
end
