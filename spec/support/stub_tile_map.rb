# frozen_string_literal: true

# A tile map built by hand, for specs that draw one without parsing a `.tmx`.
#
#   map = StubTileMap.new(
#     layers: [[1, 2, 0, 3], [0, 0, 4, 0]], above: [false, true], solid: [3],
#     animations: { 1 => [[1, 0.1], [2, 0.1]] }, orientations: { [0, 1, 0] => [1, false] }
#   )
#
# `RGame::Core::TileMapRenderer` calls a map by method name and never asks its
# class, so this is a faithful map as far as it is concerned — which is checked
# rather than assumed: it is run against the same 'a tile map' contract as
# `RGame::Engine::TileMap` (see stub_tile_map_spec.rb).
#
# Layers are flat tile-id Arrays in reading order, `width * height` long, so a
# spec can see the map it is describing. `animations` is
# `{ tile => [[tile, seconds], ...] }`, and `orientations` is
# `{ [layer, col, row] => [quarter_turns, mirrored] }` for the turned cells.
#
# It names no Engine class, because the Core suite loads it too.
class StubTileMap
  # One layer, as far as a reader of the map asks about it.
  Layer = Data.define(:above) do
    def above? = above
  end

  # How a cell is turned, answering what `TileMap::Orientation` answers.
  Orientation = Data.define(:quarter_turns, :mirrored) do
    def mirrored? = mirrored
    def identity? = quarter_turns.zero? && !mirrored
  end

  IDENTITY = Orientation.new(quarter_turns: 0, mirrored: false)

  attr_reader :width, :height, :tile_width, :tile_height

  def initialize(layers:, width: 2, height: 2, tile_width: 16, tile_height: 16,
                 above: [], solid: [], animations: {}, orientations: {})
    @cells = layers
    @layers = Array.new(layers.length) { Layer.new(above: above.fetch(it, false)) }
    @width = width
    @height = height
    @tile_width = tile_width
    @tile_height = tile_height
    @solid = solid
    @animations = animations
    @orientations = orientations.transform_values { |turns, mirrored| Orientation.new(turns, mirrored) }
  end

  def layer_count = @layers.length
  def layer(index) = @layers.fetch(index)

  def tile(layer, col, row)
    cells = @cells.fetch(layer)
    return 0 unless col >= 0 && row >= 0 && col < @width && row < @height

    cells[(row * @width) + col]
  end

  def orientation(layer, col, row) = @orientations.fetch([layer, col, row], IDENTITY)

  def solid?(tile) = @solid.include?(tile)

  def animated_tiles = @animations.keys

  # The frame showing after `elapsed` seconds, looping. Mirrors
  # RGame::Engine::TileMap's own arithmetic, each frame ending where the
  # durations before it add up to: a stand-in that rounded differently would
  # send the renderer's spec chasing a frame the game never shows.
  def frame_tile(tile, elapsed)
    frames = @animations[tile] or return tile

    ends = 0.0
    into = elapsed % frames.sum { |_tile, seconds| seconds }
    frames.each do |shown, seconds|
      ends += seconds
      return shown if into < ends
    end
    frames.last.first
  end

  def pixel_width = @width * @tile_width
  def pixel_height = @height * @tile_height
end
