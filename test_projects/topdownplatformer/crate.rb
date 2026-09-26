# frozen_string_literal: true

module TopDownPlatformer
  # Something a hero pushes by walking into it. It falls into a gap as a hero does,
  # and comes back where it first stood. It draws as a plain rect, centred on its
  # node, so its centre is where it stands.
  class Crate < Engine::Node2D
    SIZE = 16

    COLOR = Util::Color.new(176, 128, 72)

    def initialize(**)
      super
      add_component(Engine::Components::BoxCollider.new(width: SIZE, height: SIZE, offset_x: -SIZE / 2,
                                                        offset_y: -SIZE / 2, layer: :crate))
      add_component(Engine::Components::Pushable.new(blocked_by: %i[tiles crate hero]))
      add_component(Engine::Components::Footing.new(coyote: 0))
      add_component(Engine::Components::Respawn.new(flash: 0.5))
    end

    def _draw(renderer, _view)
      renderer.rect(-SIZE / 2, -SIZE / 2, SIZE, SIZE, color: COLOR)
    end
  end
end
