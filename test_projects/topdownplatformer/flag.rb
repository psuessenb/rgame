# frozen_string_literal: true

# A checkpoint: a signpost until a hero reaches it, and a banner after. It stands
# on its node's origin, where a hero who reached it comes back.
#
# Its Checkpoint moves the Respawn point of the hero who touched it, then says so,
# and the flag hands its name to that hero for their status line. A flag over a
# gap raises as the course loads.
class Flag < RGame::Engine::Node2D
  TILES = 'tiles.json'
  SIZE = 16
  POST = [6, 11].freeze
  BANNER = [7, 11].freeze

  def initialize(name:, **)
    super(**)
    add_component(RGame::Engine::Components::BoxCollider.new(width: SIZE, height: SIZE, offset_x: -SIZE / 2,
                                                             offset_y: -SIZE, layer: :checkpoint))
    add_component(RGame::Engine::Components::Checkpoint.new(by: :hero)).on_reached do |other|
      @tile = BANNER
      other.node.reach(name)
    end
    @tile = POST
  end

  def _draw(renderer, _view)
    row, column = @tile
    renderer.sprite(TILES, row, column, -SIZE / 2, -SIZE)
  end
end
