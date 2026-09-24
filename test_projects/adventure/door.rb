# frozen_string_literal: true

# A door or a warp pad, built from one object on a room's map.
#
# A hero's feet box touching its box asks the world's rooms for a move, to the
# room and entrance the object's properties name, and the door stays where it
# is. A warp's room hands over its own name as `to`. A door marked `party` moves
# every hero the world holds, from whichever room they stand in; any other door
# moves the hero who touched it.
#
# It draws a square and its name, so a driven run can tell which room a region
# shows by the doors drawn in it.
class Door < RGame::Engine::Node2D
  COLORS = {
    'door' => RGame::Util::Color.new(150, 104, 56),
    'warp' => RGame::Util::Color.new(150, 96, 210, 200)
  }.freeze

  def initialize(object:, world:, to: object.properties.fetch('to').to_sym)
    super(x: object.x, y: object.y, width: object.width, height: object.height)
    @name = object.name
    @color = COLORS.fetch(object.class_name)
    entrance = object.properties.fetch('entrance')
    party = object.properties.fetch('party', false)
    add_component(RGame::Engine::Components::BoxCollider.new(width: object.width, height: object.height,
                                                             layer: :door))
    add_component(RGame::Engine::Components::Collectable.new(by: :hero, free: false)).on_collected do |other|
      world.rooms.move(party ? world.heroes : other.node, to:, entrance:)
    end
  end

  def _draw(renderer, _view)
    renderer.rect(0, 0, width, height, color: @color)
    renderer.text(@name, 0, -12)
  end
end
