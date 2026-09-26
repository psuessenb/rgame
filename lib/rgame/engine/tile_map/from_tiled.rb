# frozen_string_literal: true

require_relative '../tiled/map'

module RGame
  module Engine
    # The transform from the parse to the runtime view, and the one file
    # outside `lib/rgame/engine/tiled/` that names `Tiled::`. Everything the
    # file format says in its own terms is turned into the game's here, once:
    #
    # - a gid, counted across tilesets from each one's `firstgid`, becomes a
    #   dense tile id, and a gid no tileset covers raises;
    # - Tiled's three flip bits become an `Orientation`;
    # - the group tree becomes the flat layer list;
    # - frame durations in milliseconds become the second each frame ends at,
    #   summed in whole milliseconds so that no rounding moves a boundary;
    # - a tile object's corner moves from the point its tileset's object
    #   alignment names, bottom-left unless the tileset says otherwise, to its
    #   top-left, and every position moves by the infinite-map origin so that
    #   cell `(0, 0)` is the map's top-left;
    # - a tile object with no class takes its tile's, and its tile's
    #   properties sit under its own, as Tiled shows them;
    # - an object layer's draw order becomes `y_sort?`, and the bool properties
    #   `above` and `actors` become `above?` and `actors?`, each checked once;
    # - a tileset's drawing offset becomes each of its tiles' `tile_offset`.
    class TileMap
      # Builds a map from a `Tiled::Map`. The only way one is built.
      def self.from_tiled(tiled_map) = FromTiled.new(tiled_map).map

      # One run of the transform over one parsed map.
      class FromTiled
        FLIPS = [0, 4, 6, 2, 5, 1, 3, 7].freeze

        # Where each alignment's point sits in a tile object's box, as the
        # fraction of its width across and of its height down.
        ANCHORS = { top_left: [0.0, 0.0], top: [0.5, 0.0], top_right: [1.0, 0.0],
                    left: [0.0, 0.5], center: [0.5, 0.5], right: [1.0, 0.5],
                    bottom_left: [0.0, 1.0], bottom: [0.5, 1.0], bottom_right: [1.0, 1.0],
                    unspecified: [0.0, 1.0] }.freeze

        def initialize(tiled)
          @tiled = tiled
          @shift_x = tiled.origin_col * tiled.tile_width
          @shift_y = tiled.origin_row * tiled.tile_height
          @gids = []
          @layers = []
          @cells = []
          @orientations = []
          @objects = []
        end

        def map
          @table = tile_table
          flatten(@tiled.layers, [])
          TileMap.new(width: @tiled.width, height: @tiled.height,
                      tile_width: @tiled.tile_width, tile_height: @tiled.tile_height,
                      layers: @layers, cells: @cells,
                      orientations: (@orientations if @orientations.any? { it&.any?(&:nonzero?) }),
                      objects: @objects, properties: @tiled.properties,
                      source: Source.new(path: @tiled.source_path, parser_version: Tiled::PARSER_VERSION),
                      **@table)
        end

        private

        def tile_table
          table = { tile_table: [nil], solid: [false], tile_classes: [nil],
                    tile_properties: [Properties::EMPTY], frames: [nil], tile_offsets: [NO_OFFSET] }
          @tiled.tilesets.each_with_index do |ref, index|
            offset = offset_of(ref.tileset)
            local_ids(ref.tileset).each { add_tile(table, ref, index, it, offset) }
          end
          @tiled.tilesets.each { |ref| animate(table[:frames], ref) }
          table
        end

        def local_ids(tileset) = tileset.collection? ? tileset.tiles.keys.sort : (0...tileset.tile_count)

        def offset_of(tileset)
          return NO_OFFSET if tileset.offset_x.zero? && tileset.offset_y.zero?

          [tileset.offset_x, tileset.offset_y].freeze
        end

        def add_tile(table, ref, index, local_id, offset)
          tile = ref.tileset.tile(local_id)
          @gids[ref.firstgid + local_id] = table[:tile_table].size
          table[:tile_table] << TileSource.new(tileset: index, local_id: local_id)
          table[:solid] << (tile ? !tile.collision_shapes.empty? : false)
          table[:tile_classes] << (tile.class_name unless tile.nil? || tile.class_name.empty?)
          table[:tile_properties] << (tile ? tile.properties : Properties::EMPTY)
          table[:frames] << nil
          table[:tile_offsets] << offset
        end

        def animate(frames, ref)
          ref.tileset.tiles.each_value do |tile|
            next unless tile.animated? && tile.frames.sum(&:duration_ms).positive?

            where = "tileset '#{ref.tileset.name}', tile #{tile.id}"
            elapsed_ms = 0
            frames[tile_of(ref.firstgid + tile.id) { where }] = tile.frames.map do |frame|
              elapsed_ms += frame.duration_ms
              [tile_of(ref.firstgid + frame.tile_id) { "the animation of #{where}" }, elapsed_ms / 1000.0]
            end
          end
        end

        def tile_of(raw_gid)
          gid = raw_gid & Tiled::GID_MASK
          return 0 if gid.zero?

          @gids[gid] or raise Tiled::FormatError, "#{yield} names gid #{gid}, which no tileset in #{file} covers"
        end

        def orientation_of(raw_gid)
          FLIPS[((raw_gid >> 31) & 1) | (((raw_gid >> 30) & 1) << 1) | (((raw_gid >> 29) & 1) << 2)]
        end

        def flatten(layers, groups)
          layers.each do |layer|
            path = groups + [layer.name]
            actors = actors?(layer, path)
            next flatten(layer.layers, path) if layer.is_a?(Tiled::GroupLayer)

            common = { index: @layers.size, path: path, class_name: layer.class_name,
                       visible: layer.effective_visible?, opacity: layer.effective_opacity,
                       above: mark(layer, 'above'), properties: layer.properties }
            @layers << runtime_layer(layer, common, actors)
            tiles = layer.is_a?(Tiled::TileLayer)
            @cells << (layer.gids.each_with_index.map { |raw, cell| tile_of(raw) { cell_name(layer, cell) } } if tiles)
            @orientations << (layer.gids.map { orientation_of(it) } if tiles)
            layer.objects.each { @objects << object(it, common[:index]) } if layer.is_a?(Tiled::ObjectLayer)
          end
        end

        def runtime_layer(layer, common, actors)
          case layer
          when Tiled::TileLayer then Layer.new(kind: :tile, **common)
          when Tiled::ObjectLayer then ObjectLayer.new(y_sort: layer.draw_order == :topdown, actors: actors, **common)
          when Tiled::ImageLayer
            ImageLayer.new(image: layer.image&.source,
                           offset_x: layer.offset_x - @shift_x, offset_y: layer.offset_y - @shift_y,
                           repeat_x: layer.repeat_x?, repeat_y: layer.repeat_y?, **common)
          end
        end

        def mark(layer, name)
          value = layer.properties.fetch(name, false)
          return value if [true, false].include?(value)

          raise Tiled::FormatError, "layer '#{layer.name}' in #{file} has an '#{name}' property of " \
                                    "#{value.inspect}; make it a bool property in Tiled"
        end

        def actors?(layer, path)
          return false unless mark(layer, 'actors')

          marked = path.join('/')
          unless layer.is_a?(Tiled::ObjectLayer)
            raise Tiled::FormatError, "layer '#{marked}' in #{file} is marked 'actors', and only an object layer " \
                                      'holds actors; move the mark to one'
          end
          if @actors
            raise Tiled::FormatError, "layers '#{@actors}' and '#{marked}' in #{file} are both marked 'actors'; " \
                                      'keep the mark on one'
          end
          unless layer.effective_visible?
            raise Tiled::FormatError, "layer '#{marked}' in #{file} is marked 'actors' and hidden, so no actor " \
                                      'spawned into it would draw; show the layer, or move the mark to one shown'
          end
          @actors = marked
          true
        end

        def file = @tiled.source_path || 'the map'

        def cell_name(layer, cell)
          row, col = cell.divmod(layer.width)
          "layer '#{layer.name}' at column #{col}, row #{row}"
        end

        def object(object, layer)
          tile = object.gid && tile_of(object.gid) { "object #{object.id}" }&.nonzero?
          x = object.x - @shift_x
          y = object.y - @shift_y
          points = object.points.map { |px, py| [x + px, y + py].freeze }.freeze
          x, y = top_left(x, y, object, tile) if tile
          MapObject.new(id: object.id, name: object.name, class_name: class_of(object, tile), layer: layer,
                        x: x, y: y, width: object.width, height: object.height, rotation: object.rotation,
                        tile: tile, orientation: Orientation::ALL[orientation_of(object.gid || 0)],
                        visible: object.visible?, shape: object.shape, points: points,
                        properties: properties_of(object, tile))
        end

        def class_of(object, tile)
          return object.class_name unless tile && object.class_name.empty?

          @table[:tile_classes][tile] || ''
        end

        def properties_of(object, tile)
          inherited = tile ? @table[:tile_properties][tile] : Properties::EMPTY
          return object.properties if inherited.empty?
          return inherited if object.properties.empty?

          Properties.new(inherited.to_h.merge(object.properties.to_h))
        end

        def top_left(x, y, object, tile)
          tileset = @tiled.tilesets[@table[:tile_table][tile].tileset].tileset
          across, down = ANCHORS.fetch(tileset.object_alignment)
          dx = -across * object.width
          dy = -down * object.height
          radians = object.rotation * Math::PI / 180.0
          cos = Math.cos(radians)
          sin = Math.sin(radians)
          [x + (dx * cos) - (dy * sin), y + (dx * sin) + (dy * cos)]
        end
      end
      private_constant :FromTiled
    end
  end
end
