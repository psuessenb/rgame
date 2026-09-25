# frozen_string_literal: true

require 'zlib'

# Draws examples/assets/pits.png: two 16x16 tiles for a pit in Kenney's Tiny
# Town, side by side.
#
#   ruby tools/draw_pit_tiles.rb
#
# Tile 0 is the pit: near-black, flecked a shade lighter so it reads as depth
# rather than a hole in the picture. Tile 1 is the pit's north edge, for a gap
# cell with floor north of it: the dark outline Tiny Town draws everything
# with, then a face of earth in the tileset's two dirt colours, striped, that
# darkens into the pit.
#
# It needs only Ruby and zlib, which ship with Ruby, and writes the PNG by hand:
# a signature, an IHDR, one IDAT and an IEND. Every pixel is a formula of its
# position, so a second run writes the same bytes.
module PitTiles
  SIZE = 16
  PATH = File.expand_path('../examples/assets/pits.png', __dir__)

  # Tiny Town's own outline and dirt colours, read off tileset.png, and three
  # shades of the dark they fall into.
  OUTLINE = [63, 38, 49].freeze
  DIRT = [207, 130, 84].freeze
  DIRT_STRIPE = [168, 98, 66].freeze
  DUSK = [112, 66, 58].freeze
  PIT = [34, 20, 28].freeze
  FLECK = [48, 30, 40].freeze

  module_function

  def pit(x, y) = ((x * 7) + (y * 13)) % 23 < 2 ? FLECK : PIT

  def edge(x, y)
    return OUTLINE if y.zero?
    return (x + y).even? ? DIRT_STRIPE : DIRT if y == 3
    return DIRT if y < 6
    return DUSK if y < 8
    return (x + y).even? ? DUSK : PIT if y == 8

    pit(x, y)
  end

  def pixel(x, y) = x < SIZE ? pit(x, y) : edge(x - SIZE, y)

  # rubocop:disable Game/NoNeedlessAllocation -- run once to write one file; nothing
  # here is on a per-frame path, and pack is how a PNG's bytes are written
  def png
    width = SIZE * 2
    rows = Array.new(SIZE) { |y| [0, *Array.new(width) { |x| [*pixel(x, y), 255] }.flatten].pack('C*') }
    [137, 80, 78, 71, 13, 10, 26, 10].pack('C*') +
      chunk('IHDR', [width, SIZE, 8, 6, 0, 0, 0].pack('NNCCCCC')) +
      chunk('IDAT', Zlib::Deflate.deflate(rows.join, Zlib::BEST_COMPRESSION)) +
      chunk('IEND', '')
  end

  def chunk(type, data) = [data.bytesize].pack('N') + type + data + [Zlib.crc32(type + data)].pack('N')
  # rubocop:enable Game/NoNeedlessAllocation
end

File.binwrite(PitTiles::PATH, PitTiles.png)
puts "wrote #{PitTiles::PATH}"
