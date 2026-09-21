# frozen_string_literal: true

# A tile map built by hand, for specs that draw one without parsing a `.tmx`.
#
#   map = StubTileMap.new(
#     layers: [[1, 2, 0, 3], [0, 0, 4, 0]], above: [false, true], visible: [true, false],
#     opacity: [1.0, 0.5], solid: [3], tile_offsets: { 4 => [2, -4] },
#     animations: { 1 => [[1, 0.1], [2, 0.1]] }, orientations: { [0, 1, 0] => [1, false] }
#   )
#
# `RGame::Core::TileMapRenderer` calls a map by method name and never asks its
# class, so this is a faithful map as far as it is concerned — which is checked
# rather than assumed: it is run against the same 'a tile map' contract as
# `RGame::Engine::TileMap` (see stub_tile_map_spec.rb).
#
# Layers are flat tile-id Arrays in reading order, `width * height` long, so a
# spec can see the map it is describing. `above`, `visible` and `opacity` are
# per layer, defaulting to below, shown and opaque. `animations` is
# `{ tile => [[tile, seconds], ...] }`, and `orientations` is
# `{ [layer, col, row] => [quarter_turns, mirrored] }` for the turned cells.
# `tile_offsets` is `{ tile => [x, y] }` for the tiles drawn off their cell.
# `image_layers` is `{ layer => { offset_x:, offset_y:, repeat_x:, repeat_y: } }`,
# every key optional, and such a layer's entry in `layers` is `nil`, as is an
# object layer's, whose index `object_layers` lists. `names` are the layers'
# names, `layer0`, `layer1` and so on when not given.
#
# It names no Engine class, because the Core suite loads it too.
class StubTileMap
  # One layer, as far as a reader of the map asks about it.
  Layer = Data.define(:name, :kind, :above, :visible, :opacity, :offset_x, :offset_y, :repeat_x, :repeat_y) do
    def above? = above
    def visible? = visible
    def repeat_x? = repeat_x
    def repeat_y? = repeat_y
  end

  # How a cell is turned, answering what `TileMap::Orientation` answers.
  Orientation = Data.define(:quarter_turns, :mirrored) do
    def mirrored? = mirrored
    def identity? = quarter_turns.zero? && !mirrored
  end

  IDENTITY = Orientation.new(quarter_turns: 0, mirrored: false)
  NO_OFFSET = [0, 0].freeze

  attr_reader :width, :height, :tile_width, :tile_height

  def initialize(layers:, width: 2, height: 2, tile_width: 16, tile_height: 16,
                 above: [], visible: [], opacity: [], solid: [], animations: {}, orientations: {},
                 tile_offsets: {}, image_layers: {}, object_layers: [], names: [])
    @cells = layers
    @layers = Array.new(layers.length) do |index|
      image = image_layers[index]
      kind = if image then :image
             elsif object_layers.include?(index) then :object
             else :tile
             end
      Layer.new(name: names.fetch(index, "layer#{index}"), kind: kind, above: above.fetch(index, false),
                visible: visible.fetch(index, true), opacity: opacity.fetch(index, 1.0),
                **placement(image || {}))
    end
    @width = width
    @height = height
    @tile_width = tile_width
    @tile_height = tile_height
    @solid = solid
    @animations = animations
    @tile_offsets = tile_offsets
    @orientations = orientations.transform_values { |turns, mirrored| Orientation.new(turns, mirrored) }
  end

  def layer_count = @layers.length
  def layer(index) = @layers.fetch(index)

  def layer_index(name)
    @layers.index { it.name == name } or
      raise KeyError.new("no layer '#{name}' in this map (has: #{@layers.map(&:name).join(', ')})",
                         receiver: self, key: name)
  end

  def tile(layer, col, row)
    cells = @cells.fetch(layer)
    return 0 unless cells && col >= 0 && row >= 0 && col < @width && row < @height

    cells[(row * @width) + col]
  end

  def orientation(layer, col, row) = @orientations.fetch([layer, col, row], IDENTITY)

  def solid?(tile) = @solid.include?(tile)

  def animated_tiles = @animations.keys

  def tile_offset(tile) = @tile_offsets.fetch(tile, NO_OFFSET)

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

  def cell_x(col) = col * @tile_width
  def cell_y(row) = row * @tile_height
  def col_at(world_x) = (world_x / @tile_width).floor
  def row_at(world_y) = (world_y / @tile_height).floor

  private

  def placement(image)
    { offset_x: image.fetch(:offset_x, 0), offset_y: image.fetch(:offset_y, 0),
      repeat_x: image.fetch(:repeat_x, false), repeat_y: image.fetch(:repeat_y, false) }
  end
end
