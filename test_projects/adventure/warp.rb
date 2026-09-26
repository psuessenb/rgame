# frozen_string_literal: true

module Adventure
  # A warp pad: a door into the room it stands in. Stepping on one only places
  # the hero again, at the entrance the pad names, and nothing is built or
  # freed. A room is its own scene, so the pad leads to the scene's name.
  class Warp < Door
    COLOR = Util::Color.new(150, 96, 210, 200)

    # `name:` is named here, since the builder passes an object's name only to
    # a class whose own `initialize` names it.
    #
    # @param entrance [String] the entrance in this room where the hero arrives
    def initialize(entrance:, name:, **) = super(to: nil, entrance:, name:, **)

    private

    def destination = scene.name
  end
end
