# frozen_string_literal: true

require 'rexml/document'
require 'base64'
require 'zlib'

require_relative 'tensor'
require_relative 'tileset'

module Engine
  # An orthogonal tile map parsed from a Tiled .tmx. Holds the per-layer gid
  # arrays and geometry, and answers collision queries via its Tileset.
  #
  # `parse` takes a *string*, so the parsing itself needs no filesystem at all;
  # `load` adds the file plumbing on top — reading the .tmx, following it to the
  # .tsx it names, and working out where the tileset image sits relative to
  # that. Both belong here. What does *not* is the image: a texture is a GPU
  # handle, and the renderer that owns one lives a layer below and may not name
  # this class (see CLAUDE.md, "The rule points both ways"). So `load` hands
  # back a path and stops there.
  class TileMap
    FLIP_MASK = 0x1FFFFFFF # strip Tiled's flip/rotation flags from a gid

    attr_reader :width, :height, :tile_width, :tile_height,
                :pixel_width, :pixel_height, :tileset_source, :firstgid
    attr_accessor :tileset

    # Reads a .tmx and everything it points at, returning `[map, image_path]`.
    #
    # Two values rather than one because they are two kinds of thing: the map is
    # the grid, and the path is where its pixels happen to live. Keeping the
    # second off the map means a stand-in map in a spec has one less method to
    # answer, and the renderer's protocol stays "things about the grid".
    #
    # Every path is resolved relative to the file that named it — the .tsx
    # relative to the .tmx, the image relative to the .tsx — which is what Tiled
    # itself writes and what lets a map be moved as a set.
    def self.load(tmx_path)
      map = parse(File.read(tmx_path))

      tsx_path = File.join(File.dirname(tmx_path), map.tileset_source)
      map.tileset = Tileset.parse(File.read(tsx_path), firstgid: map.firstgid)

      [map, File.join(File.dirname(tsx_path), map.tileset.image_source)]
    end

    def self.parse(tmx_string)
      root = REXML::Document.new(tmx_string).root
      tileset_el = root.elements['tileset']

      layers = []
      above = []
      root.each_element('layer') do |layer_el|
        raw = Base64.decode64(layer_el.elements['data'].text.strip)
        gids = Zlib::Inflate.inflate(raw).unpack('V*')
        gids.map! { |g| g & FLIP_MASK }
        layers << gids
        above << layer_flag?(layer_el, 'above')
      end

      new(
        width: root.attributes['width'].to_i,
        height: root.attributes['height'].to_i,
        tile_width: root.attributes['tilewidth'].to_i,
        tile_height: root.attributes['tileheight'].to_i,
        tileset_source: tileset_el.attributes['source'],
        firstgid: tileset_el.attributes['firstgid'].to_i,
        layers: layers,
        above: above
      )
    end

    # True if a layer carries a Tiled bool custom property `name` set to "true".
    def self.layer_flag?(layer_el, name)
      props = layer_el.elements['properties']
      return false unless props

      props.each_element('property') do |property|
        return property.attributes['value'] == 'true' if property.attributes['name'] == name
      end
      false
    end

    def initialize(width:, height:, tile_width:, tile_height:, tileset_source:, firstgid:, layers:, above: [])
      @width = width
      @height = height
      @tile_width = tile_width
      @tile_height = tile_height
      @pixel_width = width * tile_width
      @pixel_height = height * tile_height
      @tileset_source = tileset_source
      @firstgid = firstgid
      @above = above
      @tileset = nil
      @tiles = build_tiles(layers)
    end

    def layer_count
      @tiles.depth
    end

    # Whether a layer is drawn *above* the actors (a tree canopy, roof, etc.) rather
    # than beneath them. Marked in Tiled with a bool layer property `above`; layers
    # without it default to below. Purely a rendering distinction (collision still
    # considers every layer).
    def above_layer?(index)
      @above[index] || false
    end

    def in_bounds?(col, row)
      col >= 0 && row >= 0 && col < @width && row < @height
    end

    def gid(layer_index, col, row)
      return 0 unless in_bounds?(col, row)

      @tiles[col, row, layer_index]
    end

    # Solid if any layer has a solid tile at (col, row). Out of bounds is not solid
    # — the camera/bounds clamp keeps the player inside the map.
    def solid_tile?(col, row)
      return false unless in_bounds?(col, row)

      @tiles.depth.times { |layer| return true if @tileset.solid?(@tiles[col, row, layer]) }
      false
    end

    def solid_at?(world_x, world_y)
      solid_tile?((world_x / @tile_width).floor, (world_y / @tile_height).floor)
    end

    private

    # Pack the parsed per-layer gid rows into one flat Tensor ([col, row, layer]).
    def build_tiles(layers)
      tiles = Tensor.new(@width, @height, layers.length, initial: 0)
      layers.each_with_index do |gids, layer|
        @height.times do |row|
          base = row * @width
          @width.times { |col| tiles[col, row, layer] = gids[base + col] }
        end
      end
      tiles
    end
  end
end
