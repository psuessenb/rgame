# frozen_string_literal: true

module Adventure
  # A door built from a room's map. A hero's feet box touching its box asks the
  # world's rooms for a move, and the door stays where it is. The box stands on
  # the node's origin, the bottom centre of the object Tiled shows.
  #
  # A door marked `party` moves every hero the world holds, from whichever room
  # they stand in. Any other door moves the hero who touched it.
  #
  # It draws a square and its name, so a driven run can tell which room a region
  # shows by the doors drawn in it.
  class Door < Engine::Node2D
    COLOR = Util::Color.new(150, 104, 56)

    # How far above its box a door writes its name, in pixels.
    NAME_RISE = 12

    # @param to [Symbol] the room the door leads to
    # @param entrance [String] the entrance in that room where the hero arrives
    # @param party [Boolean] whether it moves every hero the world holds, rather than the one who touched it
    def initialize(to:, entrance:, name:, party: false, **)
      super(**)
      @to = to
      @entrance = entrance
      @name = name
      @party = party
      add_component(Components::BoxCollider.new(width:, height:, offset_x: -width / 2.0, offset_y: -height,
                                                layer: :door))
      add_component(Components::Collectable.new(by: :hero, free: false)).on_collected { move(it.node) }
    end

    def _enter_tree = @rooms = system!(Engine::Scene::Rooms)

    def _draw(renderer, _view)
      renderer.rect(-width / 2.0, -height, width, height, color: self.class::COLOR)
      renderer.text(@name, -width / 2.0, -height - NAME_RISE)
    end

    private

    def destination = @to

    def move(hero) = @rooms.move(@party ? @rooms.node.heroes : hero, to: destination, entrance: @entrance)
  end
end
