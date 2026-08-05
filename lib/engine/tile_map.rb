# frozen_string_literal: true

require 'rexml/document'
require 'base64'
require 'zlib'

module Engine
  # An orthogonal tile map parsed from a Tiled .tmx (pure; no Gosu). Holds the
  # per-layer gid arrays and geometry, and answers collision queries via its
  # Tileset. Parses from a *string* so it stays headless-testable; file IO and the
  # tileset image live in the platform layer.
  class TileMap
    FLIP_MASK = 0x1FFFFFFF # strip Tiled's flip/rotation flags from a gid

    attr_reader :width, :height, :tile_width, :tile_height,
                :pixel_width, :pixel_height, :tileset_source, :firstgid
    attr_accessor :tileset

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
