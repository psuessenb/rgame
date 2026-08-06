# frozen_string_literal: true

require 'base64'
require 'fileutils'
require 'tmpdir'
require 'zlib'

# Writes Tiled `.tmx` / `.tsx` files for the tile-map specs to load.
#
#   tmx = TiledFixture.write_map(layers: [[1, 2], [0, 3]])
#   map, image_path = RGame::Engine::TileMap.load(tmx)
#
# Generated rather than committed, for the same reason PngFixture generates its
# PNGs: what matters about a fixture is its *content*, and "layer 0 is these
# four gids, layer 1 is above" is the assertion. A checked-in .tmx would hide it
# behind a base64 blob — which is literally what Tiled writes, since layer data
# is zlib-deflated and base64-encoded.
#
# The encoder here is deliberately the smallest thing that produces what the
# parser reads, not a Tiled emulator: it writes the attributes and elements
# `TileMap.parse` and `Tileset.parse` actually look at, and nothing else.
module TiledFixture
  module_function

  # A .tmx plus the .tsx it names and the image filename that names, written as
  # real files so the relative-path resolution is exercised rather than assumed.
  #
  # `layers` is an Array of gid Arrays, one per layer, each `width * height`
  # long in reading order. `above` marks which layers carry Tiled's `above`
  # custom property.
  #
  # `tileset_subdirectory` puts the .tsx somewhere other than beside the .tmx,
  # which is the only way to tell "resolved against the map" apart from
  # "resolved against the tileset" — with both files in one directory the two
  # rules produce the same answer and a spec cannot see the difference.
  def write_map(layers:, width: 2, height: 2, tile_size: 16, above: [], firstgid: 1,
                animations: {}, image: 'tiles.png', subdirectory: nil,
                tileset_subdirectory: nil)
    map_directory = make(subdirectory)
    tileset_directory = make(subdirectory, tileset_subdirectory)

    id = next_id
    tsx_name = "tiles_#{id}.tsx"
    File.write(File.join(tileset_directory, tsx_name), tsx(tile_size, image, animations))

    source = tileset_subdirectory ? File.join(tileset_subdirectory, tsx_name) : tsx_name
    tmx_path = File.join(map_directory, "map_#{id}.tmx")
    File.write(tmx_path, tmx(layers, width, height, tile_size, source, above, firstgid))
    tmx_path
  end

  def make(*parts)
    directory = File.join(root, *parts.compact)
    FileUtils.mkdir_p(directory)
    directory
  end

  # Layer data as Tiled writes it: little-endian 32-bit gids, deflated, base64.
  def encode_layer(gids)
    Base64.strict_encode64(Zlib::Deflate.deflate(gids.pack('V*')))
  end

  def tmx(layers, width, height, tile_size, tileset_source, above, firstgid)
    body = layers.each_with_index.map do |gids, index|
      properties = if above[index]
                     '<properties><property name="above" type="bool" value="true"/></properties>'
                   else
                     ''
                   end
      <<~LAYER
        <layer width="#{width}" height="#{height}">#{properties}
          <data encoding="base64" compression="zlib">#{encode_layer(gids)}</data>
        </layer>
      LAYER
    end.join

    <<~TMX
      <?xml version="1.0" encoding="UTF-8"?>
      <map width="#{width}" height="#{height}" tilewidth="#{tile_size}" tileheight="#{tile_size}">
        <tileset firstgid="#{firstgid}" source="#{tileset_source}"/>
        #{body}
      </map>
    TMX
  end

  # `animations` is { local_id => [[tile_id, duration_ms], ...] }.
  def tsx(tile_size, image, animations)
    tiles = animations.map do |id, frames|
      frame_elements = frames.map do |tile_id, duration|
        %(<frame tileid="#{tile_id}" duration="#{duration}"/>)
      end.join
      %(<tile id="#{id}"><animation>#{frame_elements}</animation></tile>)
    end.join

    <<~TSX
      <?xml version="1.0" encoding="UTF-8"?>
      <tileset columns="4" tilewidth="#{tile_size}" tileheight="#{tile_size}">
        <image source="#{image}"/>
        #{tiles}
      </tileset>
    TSX
  end

  def root = @root ||= Dir.mktmpdir('rgame-tiled-fixtures')

  def next_id = @next_id = (@next_id || 0) + 1
end
