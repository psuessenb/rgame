# frozen_string_literal: true

require 'zlib'

# Draws examples/assets/coin.png: a gold coin turning on its vertical axis, in
# eight 16x16 frames side by side.
#
#   ruby tools/draw_coin.rb
#
# The frames cover half a turn, from face on to edge on and back, because a
# plain coin's back looks the same as its face. Frame k shows the coin turned
# by k/8 of that half turn, so its width is the face's width times the cosine
# of the angle. Edge on, it is a bar two pixels wide, lit on its left. Each
# frame has a dark outline, and a highlight on the left of the face, where the
# light stays as the coin turns.
#
# It needs only Ruby and zlib, which ship with Ruby, and writes the PNG by hand:
# a signature, an IHDR, one IDAT and an IEND. Every pixel is a formula of its
# position, so a second run writes the same bytes.
module Coin
  SIZE = 16
  FRAMES = 8
  RADIUS = 7.0
  PATH = File.expand_path('../examples/assets/coin.png', __dir__)

  # Gold, with a darker outline and rim and a paler shine.
  FACE = [240, 200, 96].freeze
  OUTLINE = [120, 78, 24].freeze
  RIM = [196, 146, 52].freeze
  SHINE = [255, 244, 184].freeze
  CLEAR = [0, 0, 0, 0].freeze

  module_function

  def half_width(frame) = RADIUS * Math.cos(Math::PI * frame / FRAMES).abs

  # Whether the pixel at (x, y) of `frame` is on the coin, measured from the
  # pixel's centre to the frame's.
  def inside?(frame, x, y)
    return false unless x.between?(0, SIZE - 1) && y.between?(0, SIZE - 1)

    across = x + 0.5 - (SIZE / 2)
    down = y + 0.5 - (SIZE / 2)
    width = half_width(frame)
    return across.abs < 1 && down.abs < RADIUS if width < 1

    ((across / width)**2) + ((down / RADIUS)**2) <= 1
  end

  def edge?(frame, x, y)
    !(inside?(frame, x - 1, y) && inside?(frame, x + 1, y) && inside?(frame, x, y - 1) && inside?(frame, x, y + 1))
  end

  # Edge on, the lit left column is the rim, and the right column and both
  # ends are the outline.
  def rim(frame, x, y)
    ends = !inside?(frame, x, y - 1) || !inside?(frame, x, y + 1)
    [*(ends || inside?(frame, x - 1, y) ? OUTLINE : RIM), 255]
  end

  def colour(frame, x, y)
    return CLEAR unless inside?(frame, x, y)
    return rim(frame, x, y) if half_width(frame) < 1
    return [*OUTLINE, 255] if edge?(frame, x, y)

    across = (x + 0.5 - (SIZE / 2)) / half_width(frame)
    down = (y + 0.5 - (SIZE / 2)) / RADIUS
    [*(across.between?(-0.7, -0.3) && down.between?(-0.55, 0.2) ? SHINE : FACE), 255]
  end

  # rubocop:disable Game/NoNeedlessAllocation -- run once to write one file; nothing
  # here is on a per-frame path, and pack is how a PNG's bytes are written
  def png
    width = SIZE * FRAMES
    rows = Array.new(SIZE) do |y|
      [0, *Array.new(width) { |x| colour(x / SIZE, x % SIZE, y) }.flatten].pack('C*')
    end
    [137, 80, 78, 71, 13, 10, 26, 10].pack('C*') +
      chunk('IHDR', [width, SIZE, 8, 6, 0, 0, 0].pack('NNCCCCC')) +
      chunk('IDAT', Zlib::Deflate.deflate(rows.join, Zlib::BEST_COMPRESSION)) +
      chunk('IEND', '')
  end

  def chunk(type, data) = [data.bytesize].pack('N') + type + data + [Zlib.crc32(type + data)].pack('N')
  # rubocop:enable Game/NoNeedlessAllocation
end

File.binwrite(Coin::PATH, Coin.png)
puts "wrote #{Coin::PATH}"
