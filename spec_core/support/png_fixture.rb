# frozen_string_literal: true

require 'zlib'
require 'tmpdir'

# Writes small PNG files for the image specs to load.
#
# The fixtures are generated rather than committed because what matters about
# them is their *content* — "row 0 is red, row 1 is blue" is the assertion, and
# a checked-in binary would hide it. Generating them also means the encoder
# here is the only thing between a spec's intent and the bytes stb decodes, so
# a failure points at one of the two rather than at an opaque file.
#
#   path = PngFixture.write(2, 2) { |x, y| y.zero? ? [255, 0, 0, 255] : [0, 0, 255, 255] }
#
# The block is called for every pixel and returns [r, g, b, a].
module PngFixture
  SIGNATURE = [137, 80, 78, 71, 13, 10, 26, 10].pack('C*')

  module_function

  # Writes a PNG into a temporary directory that lives as long as the process,
  # and returns its path. Specs never clean up individually; the whole
  # directory goes when the run ends.
  def write(width, height, name: nil, &pixel)
    path = File.join(directory, name || "fixture_#{width}x#{height}_#{next_id}.png")
    File.binwrite(path, encode(width, height, &pixel))
    path
  end

  # A greyscale PNG (colour type 0), for the path where the file's format is
  # not what the engine uploads and stb has to convert. The block returns one
  # 0..255 value per pixel.
  def write_greyscale(width, height, name: nil, &pixel)
    path = File.join(directory, name || "grey_#{width}x#{height}_#{next_id}.png")
    File.binwrite(path, encode_greyscale(width, height, &pixel))
    path
  end

  # A file that is not a PNG at all, for the "corrupt asset" path.
  def write_garbage(name: nil)
    path = File.join(directory, name || "garbage_#{next_id}.png")
    File.binwrite(path, 'this is not a PNG')
    path
  end

  def directory
    @directory ||= Dir.mktmpdir('rgame-png-fixtures')
  end

  def next_id
    @next_id = (@next_id || 0) + 1
  end

  def encode(width, height)
    # Each scanline is prefixed with a filter byte. 0 means "no filtering" —
    # the encoder's one job here is to be obviously correct, not small.
    raw = +''
    height.times do |y|
      raw << 0.chr
      width.times { |x| raw << yield(x, y).pack('C4') }
    end

    # Colour type 6 is RGBA, bit depth 8 — the format the engine uploads, so
    # nothing in the fixture path exercises a conversion the game never hits.
    header = [width, height, 8, 6, 0, 0, 0].pack('NNC5')

    SIGNATURE + chunk('IHDR', header) + chunk('IDAT', Zlib::Deflate.deflate(raw)) + chunk('IEND', '')
  end

  def encode_greyscale(width, height)
    raw = +''
    height.times do |y|
      raw << 0.chr
      width.times { |x| raw << (yield(x, y) & 0xFF).chr }
    end

    header = [width, height, 8, 0, 0, 0, 0].pack('NNC5') # colour type 0: grey

    SIGNATURE + chunk('IHDR', header) + chunk('IDAT', Zlib::Deflate.deflate(raw)) + chunk('IEND', '')
  end

  # A PNG chunk is length, type, data, then a CRC32 over type+data.
  def chunk(type, data)
    body = type + data
    [data.bytesize].pack('N') + body + [Zlib.crc32(body)].pack('N')
  end
end
