# frozen_string_literal: true

require_relative 'layer'
require_relative 'layer_data'
require_relative 'template'

module RGame
  module Engine
    module Tiled
      # A tileset as one map uses it: the gid its first tile takes in that map.
      # The `.tmx` owns the pairing, so one `.tsx` can sit at a different
      # `firstgid` in each map that names it.
      TilesetRef = Data.define(:firstgid, :tileset)

      # A Tiled map, as the `.tmx` states it: its tilesets, in `firstgid` order,
      # and its layers as the tree Tiled shows, groups and all.
      #
      # rgame reads orthogonal maps only, and raises for any other orientation.
      # An infinite map is read into a dense grid: every tile layer covers the
      # box around every non-empty chunk of every layer, `width` and `height`
      # are that box's size, and `origin_col` and `origin_row` are the Tiled
      # cell its top-left corner sits on. A fixed map has both at 0.
      #
      # `render_order` is `:right_down`, `:right_up`, `:left_down` or
      # `:left_up`, and `background_color` a `Util::Color`, or `nil` when the
      # map states none. `source_path` is the file the map was read from, or
      # `nil` for one parsed from a string without it.
      class Map
        attr_reader :orientation, :render_order, :width, :height,
                    :tile_width, :tile_height, :background_color,
                    :class_name, :properties, :tilesets, :layers,
                    :origin_col, :origin_row, :source_path

        # Reads the `.tmx` at `tmx_path`, with every tileset and template it
        # names.
        def self.load(tmx_path) = parse(File.read(tmx_path), source_path: tmx_path)

        # Parses the text of a `.tmx`. `source_path` is the file it came from:
        # external tilesets and templates are read from files relative to it,
        # and a map parsed without one may name neither.
        def self.parse(tmx_string, source_path: nil)
          Reader.new(Tiled.root(tmx_string, 'map', source_path), source_path).map
        end

        def initialize(orientation:, render_order:, width:, height:, tile_width:, tile_height:,
                       background_color:, class_name:, properties:, tilesets:, layers:,
                       infinite:, origin_col:, origin_row:, source_path: nil)
          @orientation = orientation
          @render_order = render_order
          @width = width
          @height = height
          @tile_width = tile_width
          @tile_height = tile_height
          @background_color = background_color
          @class_name = class_name
          @properties = properties
          @tilesets = tilesets.dup.freeze
          @layers = layers.dup.freeze
          @infinite = infinite
          @origin_col = origin_col
          @origin_row = origin_row
          @source_path = source_path
          freeze
        end

        # True when the file stores its layers in chunks rather than one grid.
        def infinite? = @infinite

        # Reads one `.tmx` document. Holds what the layers need from the map
        # as a whole: the box around every chunk, the tilesets by path, and
        # every template already read.
        class Reader
          Inherited = Data.define(:visible, :opacity)
          private_constant :Inherited

          def initialize(root, source_path)
            @root = root
            @source_path = source_path
            @infinite = root.attributes['infinite'] == '1'
            @firstgids = {}
            @templates = {}
            @chunks = {}.compare_by_identity
          end

          def map
            refuse_orientation
            tilesets = read_tilesets
            @origin_col, @origin_row, width, height = @infinite ? chunk_box : fixed_box
            Map.new(orientation: :orthogonal, render_order: render_order,
                    width: width, height: height,
                    tile_width: integer!('tilewidth'), tile_height: integer!('tileheight'),
                    background_color: Attributes.color(@root, 'backgroundcolor', @source_path),
                    class_name: @root.attributes['class'].to_s,
                    properties: Properties.parse(@root.elements['properties'], source_path: @source_path),
                    tilesets: tilesets, layers: layers(@root, Inherited.new(visible: true, opacity: 1.0)),
                    infinite: @infinite, origin_col: @origin_col, origin_row: @origin_row,
                    source_path: @source_path)
          end

          private

          def integer!(name) = Attributes.integer!(@root, name, @source_path)

          def fixed_box = [0, 0, integer!('width'), integer!('height')]

          def refuse_orientation
            orientation = @root.attributes['orientation'] || 'orthogonal'
            return if orientation == 'orthogonal'

            Attributes.refuse(@root, 'orientation', @source_path,
                              'rgame does not draw; it reads orthogonal maps only')
          end

          def render_order = (@root.attributes['renderorder'] || 'right-down').tr('-', '_').to_sym

          def read_tilesets
            @root.get_elements('tileset').map { tileset_ref(it) }.sort_by(&:firstgid)
          end

          def tileset_ref(element)
            firstgid = Attributes.integer!(element, 'firstgid', @source_path)
            source = element.attributes['source']
            return TilesetRef.new(firstgid, Tileset.from_element(element, source_path: @source_path)) unless source

            path = referenced(element, source, 'tileset')
            @firstgids[File.expand_path(path)] = firstgid
            TilesetRef.new(firstgid, Tileset.load(path))
          end

          def referenced(element, source, kind)
            unless @source_path || File.absolute_path?(source)
              Attributes.refuse_element(element, nil, "names the #{kind} #{source}, which a map parsed " \
                                                      'from a string cannot find; load the map from its file')
            end
            path = Attributes.path(source, @source_path)
            return path if File.file?(path)

            Attributes.refuse_element(element, @source_path, "names the #{kind} #{source}, and #{path} is not there")
          end

          def layers(parent, inherited)
            parent.elements.to_a.filter_map { layer(it, inherited) }
          end

          def layer(element, inherited)
            case element.name
            when 'layer' then TileLayer.new(**common(element, inherited), **tiles(element))
            when 'imagelayer' then ImageLayer.new(**common(element, inherited), **image(element))
            when 'objectgroup' then ObjectLayer.new(**common(element, inherited), **objects(element))
            when 'group'
              shared = common(element, inherited)
              below = Inherited.new(visible: shared[:effective_visible], opacity: shared[:effective_opacity])
              GroupLayer.new(**shared, layers: layers(element, below))
            end
          end

          def common(element, inherited)
            visible = element.attributes['visible'] != '0'
            opacity = Attributes.float(element, 'opacity', @source_path, default: 1.0)
            { id: Attributes.integer(element, 'id', @source_path),
              name: element.attributes['name'].to_s,
              class_name: element.attributes['class'].to_s,
              visible: visible, opacity: opacity,
              effective_visible: inherited.visible && visible,
              effective_opacity: inherited.opacity * opacity,
              properties: Properties.parse(element.elements['properties'], source_path: @source_path) }
          end

          def tiles(element)
            data = element.elements['data'] or Attributes.refuse_element(element, @source_path, 'has no <data>')
            return chunked(data) if @infinite

            width = Attributes.integer!(element, 'width', @source_path)
            height = Attributes.integer!(element, 'height', @source_path)
            { width: width, height: height, gids: LayerData.decode(data, data, width * height, @source_path) }
          end

          def chunked(data)
            _, _, width, height = chunk_box
            gids = Array.new(width * height, 0)
            data.get_elements('chunk').each do |chunk|
              x, y, chunk_width, = geometry(chunk)
              decoded(chunk, data).each_with_index do |gid, index|
                next if gid.zero?

                row, col = index.divmod(chunk_width)
                gids[((y + row - @origin_row) * width) + (x + col - @origin_col)] = gid
              end
            end
            { width: width, height: height, gids: gids }
          end

          def chunk_box
            @chunk_box ||= begin
              boxes = @root.get_elements('//layer/data/chunk').filter_map do |chunk|
                geometry(chunk) if decoded(chunk, chunk.parent).any?(&:nonzero?)
              end
              if boxes.empty?
                [0, 0, 0, 0]
              else
                left = boxes.map { it[0] }.min
                top = boxes.map { it[1] }.min
                [left, top, boxes.map { it[0] + it[2] }.max - left, boxes.map { it[1] + it[3] }.max - top]
              end
            end
          end

          def geometry(chunk)
            read = ->(name) { Attributes.integer!(chunk, name, @source_path) }
            [read['x'], read['y'], read['width'], read['height']]
          end

          def decoded(chunk, data)
            @chunks[chunk] ||= begin
              _, _, width, height = geometry(chunk)
              LayerData.decode(chunk, data, width * height, @source_path)
            end
          end

          def image(element)
            image = element.elements['image']
            { image: image && Tileset::Image.parse(image, source_path: @source_path),
              offset_x: Attributes.float(element, 'offsetx', @source_path, default: 0.0),
              offset_y: Attributes.float(element, 'offsety', @source_path, default: 0.0),
              repeat_x: element.attributes['repeatx'] == '1',
              repeat_y: element.attributes['repeaty'] == '1' }
          end

          def objects(element)
            { draw_order: (element.attributes['draworder'] || 'topdown').to_sym,
              objects: element.get_elements('object').map { object(it) } }
          end

          def object(element)
            source = element.attributes['template']
            return Object.parse(element, source_path: @source_path) unless source

            template(element, source).apply(element, source_path: @source_path,
                                                     firstgid_of: ->(path) { @firstgids[File.expand_path(path)] })
          end

          def template(element, source)
            path = referenced(element, source, 'template')
            @templates[File.expand_path(path)] ||= Template.load(path)
          end
        end
        private_constant :Reader
      end
    end
  end
end
