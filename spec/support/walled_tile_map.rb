# frozen_string_literal: true

# A real `RGame::Engine::TileMap`, drawn as rows of text: `#` is a solid tile,
# anything else an empty cell.
#
#   map = WalledTileMap.build(['....', '.##.', '....'])
#   map.solid_tile?(1, 1)   # => true
#
# For the specs that put a `Components::TileWorld` on a map and care only
# where the walls are. It builds the map class itself rather than a double, so
# it answers every method a `TileWorld` forwards and cannot fall behind one
# added later. The Core suite does not load it.
module WalledTileMap
  module_function

  def build(rows, tile: 16)
    engine = RGame::Engine
    empty = engine::Properties::EMPTY
    engine::TileMap.new(
      width: rows.first.length, height: rows.length, tile_width: tile, tile_height: tile,
      layers: [engine::TileMap::Layer.new(index: 0, path: ['walls'], kind: :tile, class_name: '', visible: true,
                                          opacity: 1.0, above: false, properties: empty)],
      cells: [rows.join.chars.map { it == '#' ? 1 : 0 }],
      tile_table: [nil, engine::TileMap::TileSource.new(tileset: 0, local_id: 0)],
      solid: [false, true], tile_classes: [nil, nil], tile_properties: [empty, empty], frames: [nil, nil]
    )
  end
end
