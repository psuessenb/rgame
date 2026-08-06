# frozen_string_literal: true

RSpec.describe StubTileMap do
  # The contract's hook: the stand-in is built by hand from the shape the
  # contract prescribes. RGame::Engine::TileMap's version of this parses a .tmx to
  # reach the same place — see spec/engine/tile_map_spec.rb.
  def tile_map
    yield described_class.new(
      layers: [[1, 2, 0, 3], [0, 0, 4, 0]],
      above: [false, true],
      tileset: StubTileset.new(firstgid: 1, animations: { 0 => [[0, 100], [1, 100]] })
    )
  end

  it_behaves_like 'a tile map'
end
