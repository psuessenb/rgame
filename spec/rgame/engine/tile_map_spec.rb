# frozen_string_literal: true

# Only `.load` — the file plumbing added so that `RGame::Core` never has to name
# this class. `.parse` and the geometry it produces are the engine layer's own
# and belong with the rest of that suite when it lands; what is covered here is
# the boundary work: following a .tmx to its .tsx, and a .tsx to its image.
RSpec.describe RGame::Engine::TileMap do
  # The other side of the contract RGame::Core::TileMapRenderer draws against.
  # Reaching the prescribed shape means writing a .tmx and a .tsx and parsing
  # them, where the stand-in just declares it — which is exactly the difference
  # the contract exists to hold together.
  def tile_map
    tmx = TiledFixture.write_map(
      layers: [[1, 2, 0, 3], [0, 0, 4, 0]], above: [false, true],
      animations: { 0 => [[0, 100], [1, 100]] }
    )
    map, = described_class.load(tmx)
    yield map
  end

  it_behaves_like 'a tile map'

  describe '.load' do
    it 'parses the map and attaches the tileset it names' do
      map, = described_class.load(TiledFixture.write_map(layers: [[1, 2, 3, 4]]))

      expect(map.width).to eq(2)
      expect(map.tile_width).to eq(16)
      expect(map.tileset).to be_a(RGame::Engine::Tileset)
      expect(map.gid(0, 1, 0)).to eq(2)
    end

    it 'hands back where the tileset image lives' do
      _map, image_path = described_class.load(
        TiledFixture.write_map(layers: [[0]], image: 'beach.png')
      )

      expect(File.basename(image_path)).to eq('beach.png')
    end

    it 'resolves the tileset relative to the map, not the working directory' do
      # Tiled writes relative paths, so a map in a subdirectory names its .tsx
      # relative to itself. Resolving against Dir.pwd works from the project
      # root and fails from anywhere else — including from inside a game.
      tmx = TiledFixture.write_map(layers: [[1]], subdirectory: 'levels')

      expect { described_class.load(tmx) }.not_to raise_error
    end

    it 'resolves the image relative to the tileset, not the map' do
      # One more hop, and the one that is easy to get wrong: the image path
      # comes out of the .tsx, so it is relative to *that* file. Only visible
      # with the tileset somewhere other than beside the map — which is why the
      # fixture can put it there.
      tmx = TiledFixture.write_map(layers: [[1]], subdirectory: 'levels',
                                   tileset_subdirectory: 'tilesets', image: 'beach.png')
      _map, image_path = described_class.load(tmx)

      expect(image_path).to eq(File.join(File.dirname(tmx), 'tilesets', 'beach.png'))
    end

    it 'carries the tileset firstgid through from the map' do
      # The tileset needs it to turn a map's global id into its own local one,
      # and it lives in the .tmx rather than the .tsx. A firstgid of 1 is the
      # common case and also the one that cannot catch a hardcoded 1.
      map, = described_class.load(TiledFixture.write_map(layers: [[5]], firstgid: 5))

      expect(map.tileset.firstgid).to eq(5)
      expect(map.tileset.local_id(5)).to be_zero
    end

    it 'reads a tile animation out of the tileset' do
      map, = described_class.load(
        TiledFixture.write_map(layers: [[1]], animations: { 0 => [[0, 100], [1, 100]] })
      )

      expect(map.tileset.animations).to have_key(0)
      expect(map.tileset.frame_local_id(0, 150)).to eq(1)
    end

    it 'marks the layers flagged above in the map' do
      map, = described_class.load(
        TiledFixture.write_map(layers: [[1], [2]], width: 1, height: 1, above: [false, true])
      )

      expect([map.above_layer?(0), map.above_layer?(1)]).to eq([false, true])
    end

    it 'raises when the map is not there' do
      expect { described_class.load('/no/such/level.tmx') }.to raise_error(Errno::ENOENT)
    end

    it 'raises when the tileset the map names is not there' do
      tmx = TiledFixture.write_map(layers: [[1]])
      File.write(tmx, File.read(tmx).sub(/source="[^"]+"/, 'source="gone.tsx"'))

      expect { described_class.load(tmx) }.to raise_error(Errno::ENOENT, /gone\.tsx/)
    end
  end
end
