# frozen_string_literal: true

RSpec.describe StubTileMap do
  # The contract's hook: the stand-in is built by hand from the shape the
  # contract prescribes. RGame::Engine::TileMap's version of this parses a .tmx to
  # reach the same place — see spec/rgame/engine/tile_map_spec.rb.
  def tile_map
    yield described_class.new(
      layers: [[1, 2, 0, 3], [0, 0, 4, 0], nil, nil], above: [false, true], visible: [true, false],
      opacity: [1.0, 0.5], solid: [3], tile_offsets: { 4 => [2, -4] },
      animations: { 1 => [[1, 0.1], [2, 0.1]] }, orientations: { [0, 1, 0] => [1, false] },
      image_layers: { 2 => { offset_x: 8, offset_y: 4, repeat_x: true } }, object_layers: [3], actors_layer: 3,
      names: %w[ground canopy sky spawns]
    )
  end

  it_behaves_like 'a tile map'
end
