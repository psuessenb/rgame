# frozen_string_literal: true

require 'base64'
require 'fileutils'
require 'tmpdir'
require 'zlib'

# Writes Tiled `.tsx`, `.tmx` and `.tx` files for the Tiled specs to load, and
# the `<data>` elements a layer holds in each of Tiled's encodings.
#
#   directory = TiledFixture.write_files('map.tmx' => tmx, 'tiles.tsx' => tsx)
#   TiledFixture.data([1, 0, 3, 0], encoding: :csv)
#
# Generated rather than committed: what matters about a fixture is its
# *content*, and "this layer holds these four gids" is the assertion. A
# checked-in .tmx would hide it behind a base64 blob, which is what Tiled
# writes by default.
#
# The encoder here is the smallest thing that produces what the parser reads,
# not a Tiled emulator.
module TiledFixture
  module_function

  # A .tsx holding `body` inside a `<tileset>` root with `attributes`, written
  # as a real file so `Tiled::Tileset.load` resolves against where it sits.
  def write_tileset(body = '', attributes: 'tilewidth="16" tileheight="16"', subdirectory: nil)
    path = File.join(make(subdirectory), "tiles_#{next_id}.tsx")
    File.write(path, <<~TSX)
      <?xml version="1.0" encoding="UTF-8"?>
      <tileset #{attributes}>
      #{body}
      </tileset>
    TSX
    path
  end

  # Files written together into a fresh directory, from `{ relative path =>
  # contents }`, so a map, the tilesets and templates it names, and the
  # subdirectories between them sit where the map says. Returns the directory.
  def write_files(files)
    directory = make("set_#{next_id}")
    files.each do |name, contents|
      path = File.join(directory, name)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, contents)
    end
    directory
  end

  # A `<data>` element holding `gids` in one of Tiled's encodings: `:xml`,
  # `:csv` or `:base64`, the last with `compression` nil, `:gzip`, `:zlib` or
  # `:zstd`. Tiled's zstd is not written for real; its bytes are a stand-in,
  # since rgame refuses the attribute before reading them.
  def data(gids, encoding: :base64, compression: (:zlib if encoding == :base64))
    %(<data#{data_attributes(encoding, compression)}>#{encoded(gids, encoding, compression)}</data>)
  end

  # A `<data>` element of an infinite map, from `{ [x, y] => gids }`, one
  # `<chunk>` of `size` × `size` tiles per entry.
  def chunked_data(chunks, size: 2, encoding: :csv, compression: nil)
    body = chunks.map do |(x, y), gids|
      %(<chunk x="#{x}" y="#{y}" width="#{size}" height="#{size}">#{encoded(gids, encoding, compression)}</chunk>)
    end.join
    %(<data#{data_attributes(encoding, compression)}>#{body}</data>)
  end

  def data_attributes(encoding, compression)
    return '' if encoding == :xml

    compression ? %( encoding="#{encoding}" compression="#{compression}") : %( encoding="#{encoding}")
  end

  def encoded(gids, encoding, compression)
    case encoding
    when :xml then gids.map { %(<tile gid="#{it}"/>) }.join
    when :csv then gids.join(",\n")
    when :base64 then Base64.strict_encode64(compress(gids.pack('V*'), compression))
    end
  end

  def compress(bytes, compression)
    case compression
    when nil then bytes
    when :zlib then Zlib::Deflate.deflate(bytes)
    when :gzip then Zlib.gzip(bytes)
    when :zstd then "(\xB5/\xFD".b + bytes
    end
  end

  def make(*parts)
    directory = File.join(root, *parts.compact)
    FileUtils.mkdir_p(directory)
    directory
  end

  def root = @root ||= Dir.mktmpdir('rgame-tiled-fixtures')

  def next_id = @next_id = (@next_id || 0) + 1
end
