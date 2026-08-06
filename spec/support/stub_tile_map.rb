# frozen_string_literal: true

# A tile map built by hand, for specs that draw one without parsing a `.tmx`.
#
#   map = StubTileMap.new(
#     layers: [[1, 2, 0, 3], [0, 0, 4, 0]], above: [false, true],
#     tileset: StubTileset.new(animations: { 0 => [[0, 100], [1, 100]] })
#   )
#
# `RGame::Core::TileMapRenderer` calls a map by method name and never asks its
# class, so this is a faithful map as far as it is concerned — which is checked
# rather than assumed: it is run against the same 'a tile map' contract as
# `RGame::Engine::TileMap` (see stub_tile_map_spec.rb).
#
# Layers are flat gid Arrays in reading order, `width * height` long, so a spec
# can see the map it is describing.
class StubTileMap
  attr_reader :width, :height, :tile_width, :tile_height, :tileset

  def initialize(layers:, tileset:, width: 2, height: 2, tile_width: 16, tile_height: 16,
                 above: [])
    @layers = layers
    @tileset = tileset
    @width = width
    @height = height
    @tile_width = tile_width
    @tile_height = tile_height
    @above = above
  end

  def layer_count = @layers.length
  def above_layer?(index) = @above.fetch(index, false)
  def gid(layer, col, row) = @layers[layer][(row * @width) + col]

  def pixel_width = @width * @tile_width
  def pixel_height = @height * @tile_height
end

# The tileset half of the same stand-in.
#
# `animations` is `{ local_id => [[tile_id, duration_ms], ...] }` — the shape
# `RGame::Engine::Tileset` parses out of a `.tsx`, spelled as plain Arrays so a spec
# reads as data rather than as constructor calls.
class StubTileset
  attr_reader :firstgid, :animations

  def initialize(firstgid: 1, animations: {})
    @firstgid = firstgid
    @animations = animations
  end

  def local_id(gid) = gid - @firstgid

  # The frame showing at `ms`, cycling. Mirrors RGame::Engine::Tileset's own
  # arithmetic rather than approximating it: a stand-in that rounded differently
  # would send the renderer's spec chasing a frame the game never shows.
  def frame_local_id(local, ms)
    frames = @animations[local]
    return local unless frames

    remaining = ms % frames.sum { |_tile_id, duration| duration }
    frames.each do |tile_id, duration|
      return tile_id if remaining < duration

      remaining -= duration
    end
    frames.last.first
  end
end
