# frozen_string_literal: true

require 'rexml/document'
require_relative 'tile'

module RGame
  module Engine
    module Tiled
      # A Tiled tileset, as the `.tsx` or the embedded `<tileset>` states it:
      # either one sheet image cut into a grid, or a collection of images with
      # one file per tile.
      #
      # `margin` is the border around a sheet and `spacing` the gap between its
      # tiles, both in pixels and 0 when the file leaves them out. `offset_x`
      # and `offset_y` are the tileset's drawing offset. `tiles` holds only the
      # tiles the file says something about, keyed by local id, so a plain
      # sheet tile has no entry and `tile` answers `nil` for it.
      #
      # It has no `firstgid`: that pairing belongs to the map that uses the
      # tileset, and one `.tsx` can sit at a different `firstgid` in each map.
      class Tileset
        # An image file a tileset or tile names: its path, resolved relative to
        # the file that named it, and the size the file states. Never a texture.
        Image = Data.define(:source, :width, :height) do
          # Builds the record from an `<image>` REXML element. Raises for an
          # image embedded as data, which rgame does not read.
          def self.parse(element, source_path: nil)
            source = element.attributes['source'] or
              Attributes.refuse_element(element, source_path, 'embeds its image data; save the image as a file')
            new(source: Attributes.path(source, source_path),
                width: Attributes.integer(element, 'width', source_path),
                height: Attributes.integer(element, 'height', source_path))
          end
        end

        attr_reader :name, :class_name, :tile_width, :tile_height,
                    :spacing, :margin, :tile_count, :columns,
                    :image, :offset_x, :offset_y, :tiles, :properties

        # Reads the `.tsx` at `tsx_path`, resolving its paths against it.
        def self.load(tsx_path) = parse(File.read(tsx_path), source_path: tsx_path)

        # Parses the text of a `.tsx`. `source_path` is the file it came from,
        # which every path in it resolves against; without one, paths stay as
        # written.
        def self.parse(tsx_string, source_path: nil)
          root = REXML::Document.new(tsx_string).root
          unless root&.name == 'tileset'
            where = source_path ? "#{source_path} " : ''
            raise FormatError, "#{where}is not a Tiled tileset: its root element is not <tileset>"
          end
          from_element(root, source_path: source_path)
        rescue REXML::ParseException => e
          raise FormatError, "#{source_path || 'the tileset'} is not well-formed XML: #{e.message.lines.first}"
        end

        # Parses a `<tileset>` REXML element: a `.tsx`'s root, or a tileset
        # embedded in a `.tmx`, in which case `source_path` is the map.
        def self.from_element(element, source_path: nil)
          image = element.elements['image']
          offset = element.elements['tileoffset']
          new(name: element.attributes['name'].to_s,
              class_name: element.attributes['class'].to_s,
              tile_width: Attributes.integer!(element, 'tilewidth', source_path),
              tile_height: Attributes.integer!(element, 'tileheight', source_path),
              spacing: Attributes.integer(element, 'spacing', source_path, default: 0),
              margin: Attributes.integer(element, 'margin', source_path, default: 0),
              tile_count: Attributes.integer(element, 'tilecount', source_path),
              columns: Attributes.integer(element, 'columns', source_path),
              image: image && Image.parse(image, source_path: source_path),
              offset_x: offset ? Attributes.integer(offset, 'x', source_path, default: 0) : 0,
              offset_y: offset ? Attributes.integer(offset, 'y', source_path, default: 0) : 0,
              tiles: element.get_elements('tile').to_h do |tile|
                parsed = Tile.parse(tile, source_path: source_path)
                [parsed.id, parsed]
              end,
              properties: Properties.parse(element.elements['properties'], source_path: source_path),
              source_path: source_path)
        end

        def initialize(name:, class_name:, tile_width:, tile_height:, spacing:, margin:, tile_count:, columns:,
                       image:, offset_x:, offset_y:, tiles:, properties:, source_path: nil)
          @name = name
          @class_name = class_name
          @tile_width = tile_width
          @tile_height = tile_height
          @spacing = spacing
          @margin = margin
          @image = image
          @offset_x = offset_x
          @offset_y = offset_y
          @tiles = tiles.dup.freeze
          @properties = properties
          @columns = columns || counted_columns(source_path)
          @tile_count = tile_count || counted_tiles(source_path)
          freeze
        end

        # True when the tileset has no sheet and every tile names its own image.
        def collection? = @image.nil?

        # The `Tile` the file describes at `local_id`, or `nil` when it says
        # nothing about that tile beyond its place in the sheet.
        def tile(local_id) = @tiles[local_id]

        private

        def counted_columns(source_path)
          collection? ? 0 : fit(@image.width, @tile_width, 'columns', 'width', source_path)
        end

        def counted_tiles(source_path)
          return @tiles.size if collection?

          @columns * fit(@image.height, @tile_height, 'tilecount', 'height', source_path)
        end

        def fit(length, tile_length, missing, side, source_path)
          unless length
            where = source_path ? " in #{source_path}" : ''
            raise FormatError, "tileset '#{@name}'#{where} states no #{missing}, and its image no #{side} to count from"
          end
          (length - (2 * @margin) + @spacing) / (tile_length + @spacing)
        end
      end
    end
  end
end
