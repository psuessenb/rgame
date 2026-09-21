# frozen_string_literal: true

module RGame
  module Engine
    # One object from a map's object layers, in the game's coordinates: pixels,
    # with the map's top-left corner at `(0, 0)`.
    #
    # `(x, y)` is the object's top-left corner for every shape, a tile object
    # included, and `rotation` turns the object clockwise, in degrees, about
    # that corner. `points` are the corners of a polygon or polyline in the
    # same coordinates, before `rotation`, and empty for any other shape.
    #
    # `tile` is the map's own id for a tile object, or `nil` for a shape, and
    # `orientation` says how that tile is turned. `shape` is `:rectangle`,
    # `:ellipse`, `:point`, `:polygon`, `:polyline` or `:text`. `layer` is the
    # index of the layer the object sits in, as `TileMap#layer` counts them.
    MapObject = Data.define(:id, :name, :class_name, :layer, :x, :y, :width, :height, :rotation,
                            :tile, :orientation, :visible, :shape, :points, :properties) do
      # False when the designer hid the object in Tiled.
      def visible? = visible
    end
  end
end
