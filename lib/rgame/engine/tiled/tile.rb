# frozen_string_literal: true

require_relative 'object'

module RGame
  module Engine
    module Tiled
      # One step of a tile's animation: the local id to show, and for how long,
      # in the milliseconds the file states.
      Frame = Data.define(:tile_id, :duration_ms)

      # One `<tile>` of a tileset: everything the file says about a single tile
      # beyond its place in the sheet.
      #
      # `image` is set only in a collection of images, where each tile names its
      # own file. `frames` is empty for a tile that does not animate.
      # `collision_shapes` are the objects drawn on the tile in Tiled's
      # collision editor, geometry included; the runtime view keeps their class
      # and properties and treats any shape as a solid cell.
      Tile = Data.define(:id, :class_name, :properties, :image, :frames, :collision_shapes) do
        # Builds the record from a `<tile>` REXML element. `source_path` is the
        # file it came from, which the tile's image resolves against.
        def self.parse(element, source_path: nil)
          image = element.elements['image']
          new(id: Attributes.integer!(element, 'id', source_path),
              class_name: (element.attributes['type'] || element.attributes['class']).to_s,
              properties: Properties.parse(element.elements['properties'], source_path: source_path),
              image: image && Tileset::Image.parse(image, source_path: source_path),
              frames: frames(element, source_path),
              collision_shapes: collision_shapes(element, source_path))
        end

        def self.frames(element, source_path)
          element.get_elements('animation/frame').map do |frame|
            Frame.new(tile_id: Attributes.integer!(frame, 'tileid', source_path),
                      duration_ms: Attributes.integer!(frame, 'duration', source_path))
          end.freeze
        end

        def self.collision_shapes(element, source_path)
          element.get_elements('objectgroup/object').map do |object|
            Object.parse(object, source_path: source_path)
          end.freeze
        end
        private_class_method :frames, :collision_shapes

        def animated? = !frames.empty?
      end
    end
  end
end
