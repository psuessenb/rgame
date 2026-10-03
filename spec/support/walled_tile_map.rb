# frozen_string_literal: true

# A real `RGame::Engine::TileMap`, drawn as rows of text: `#` is a solid tile,
# `~` a gap tile, anything else an empty cell.
#
#   map = WalledTileMap.build(['....', '.#~.', '....'])
#   map.solid_tile?(1, 1)   # => true
#   map.gap_tile?(2, 1)     # => true
#
# For the specs that put a `Components::TileWorld` on a map and care only
# where the walls and the gaps are. It builds the map class itself rather than a double, so
# it answers every method a `TileWorld` forwards and cannot fall behind one
# added later. The Core suite does not load it.
#
# `objects:` names places on the map, in an object layer of their own. An entry
# `[name, x, y]` is a point object, and `[name, x, y, width, height]` a
# rectangle with its top-left corner at `(x, y)`. Their ids count from 1, in
# the order given.
#
#   WalledTileMap.build(['....'], objects: [['gate', 8, 8], ['sign', 32, 0, 16, 16]])
module WalledTileMap
  TILES = { '#' => 1, '~' => 2 }.freeze

  module_function

  def build(rows, tile: 16, objects: [])
    engine = RGame::Engine
    empty = engine::Properties::EMPTY
    layers = [engine::TileMap::Layer.new(index: 0, path: ['walls'], kind: :tile, class_name: '', visible: true,
                                         opacity: 1.0, properties: empty)]
    cells = [rows.join.chars.map { TILES.fetch(it, 0) }]
    unless objects.empty?
      layers << engine::TileMap::ObjectLayer.new(index: 1, path: ['places'], class_name: '', visible: true,
                                                 opacity: 1.0, properties: empty, y_sort: false)
      cells << nil
    end
    engine::TileMap.new(
      width: rows.first.length, height: rows.length, tile_width: tile, tile_height: tile, layers:, cells:,
      tile_table: [nil, engine::TileMap::TileSource.new(tileset: 0, local_id: 0),
                   engine::TileMap::TileSource.new(tileset: 0, local_id: 1)],
      solid: [false, true, false], tile_classes: [nil, nil, engine::TileMap::GAP],
      tile_properties: [empty, empty, empty], frames: [nil, nil, nil],
      objects: objects.each_with_index.map { |entry, index| map_object(entry, index + 1) }
    )
  end

  def map_object((name, x, y, width, height), id)
    engine = RGame::Engine
    engine::MapObject.new(id:, name:, class_name: '', layer: 1, x: x.to_f, y: y.to_f, width: width.to_f,
                          height: height.to_f, rotation: 0.0, tile: nil,
                          orientation: engine::TileMap::Orientation::IDENTITY, visible: true,
                          shape: width ? :rectangle : :point, points: [], properties: engine::Properties::EMPTY)
  end
end
