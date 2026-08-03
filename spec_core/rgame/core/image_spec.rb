# frozen_string_literal: true

RSpec.describe RGame::Core::Image do
  # Decoding and uploading need a real GL context, which is what this suite
  # exists for. The arithmetic underneath — which rectangle a subimage covers,
  # how that becomes texture coordinates — is pure C and is covered without a
  # display by test/test_texture.c.
  let(:app) { RGame::Core::App.new(width: 200, height: 150, caption: 'image spec') }

  # 4x2 pixels, distinguishable per pixel so a size assertion cannot pass by
  # accident on a square.
  let(:path) { PngFixture.write(4, 2) { |x, y| [x * 60, y * 100, 0, 255] } }

  # How many uploads exist right now, after collecting whatever is unreachable.
  #
  # The settle is not optional. The counter is process-wide, so images dropped
  # by *earlier* examples are still counted until a collection runs — and it
  # runs at a moment nothing controls, which without this makes a baseline
  # taken at the start of an example disagree with the count taken at the end.
  def live_textures
    3.times { GC.start(full_mark: true, immediate_sweep: true) }
    described_class.debug_live_textures
  end

  describe '.new' do
    it 'reports the size of the decoded file' do
      image = described_class.new(app, path)

      expect(image.width).to eq(4)
      expect(image.height).to eq(2)
    end

    it 'decodes a file whose pixels are not RGBA' do
      # A greyscale or palette PNG is asked of stb as RGBA regardless, so the
      # upload has one format to handle. Without that, a hand-exported asset
      # would load as garbage rather than fail loudly.
      grey = PngFixture.write_greyscale(3, 5) { |x, y| (x + y) * 20 }
      image = described_class.new(app, grey)

      expect([image.width, image.height]).to eq([3, 5])
    end

    it 'raises LoadError naming a file it cannot read' do
      expect { described_class.new(app, '/no/such/sprite.png') }
        .to raise_error(described_class::LoadError, %r{/no/such/sprite\.png})
    end

    it 'raises LoadError for a file that is not an image' do
      expect { described_class.new(app, PngFixture.write_garbage) }
        .to raise_error(described_class::LoadError, /could not decode/)
    end

    it 'refuses anything that is not an App' do
      expect { described_class.new(Object.new, path) }.to raise_error(TypeError)
    end
  end

  describe '#subimage' do
    it 'is a region of the original, in its own coordinates' do
      sub = described_class.new(app, path).subimage(1, 0, 2, 2)

      expect([sub.width, sub.height]).to eq([2, 2])
    end

    it 'composes, so a slice of a slice stays inside it' do
      sub = described_class.new(app, path).subimage(1, 0, 3, 2)

      expect { sub.subimage(2, 0, 2, 2) }.to raise_error(ArgumentError)
      expect(sub.subimage(2, 0, 1, 2).width).to eq(1)
    end

    it 'raises rather than returning nil for a rect that does not fit' do
      # nil would travel a long way before failing as a NoMethodError with
      # nothing left pointing at the bad coordinates.
      expect { described_class.new(app, path).subimage(0, 0, 99, 99) }
        .to raise_error(ArgumentError, /does not fit in a 4x2 image/)
    end

    it 'shares the upload rather than decoding again' do
      image = described_class.new(app, path)
      before = live_textures

      slices = Array.new(10) { image.subimage(0, 0, 2, 2) }

      expect(slices.size).to eq(10)
      expect(live_textures).to eq(before)
    end
  end

  describe 'tiles' do
    let(:sheet) { described_class.new(app, PngFixture.write(6, 4) { |_x, _y| [1, 2, 3, 255] }) }

    it 'counts only whole tiles' do
      expect(sheet.tile_count(2, 2)).to eq(6)  # 3 x 2
      expect(sheet.tile_count(4, 4)).to eq(1)  # the right two columns are padding
      expect(sheet.tile_count(9, 9)).to eq(0)
    end

    it 'cuts each tile to the requested size' do
      tile = sheet.tile(2, 2, 5)

      expect([tile.width, tile.height]).to eq([2, 2])
    end

    it 'raises IndexError past the end' do
      expect { sheet.tile(2, 2, 6) }.to raise_error(IndexError, /6 tiles of 2x2/)
    end

    it 'returns them all in reading order from #tiles' do
      expect(sheet.tiles(2, 2).size).to eq(6)
    end

    it 'yields them without building an Array from #each_tile' do
      expect(sheet.each_tile(2, 2).to_a.size).to eq(6)
    end
  end

  describe '.load_tiles' do
    it 'slices a file in one step' do
      tiles = described_class.load_tiles(app, PngFixture.write(8, 8) { [9, 9, 9, 255] }, 4, 4)

      expect(tiles.size).to eq(4)
      expect(tiles.map(&:width)).to all(eq(4))
    end

    it 'uploads the file once however many tiles come out of it' do
      before = live_textures

      tiles = described_class.load_tiles(app, PngFixture.write(64, 64) { [1, 1, 1, 255] }, 4, 4)

      expect(tiles.size).to eq(256)
      expect(live_textures).to eq(before + 1)
    end
  end

  describe 'texture lifetime' do
    # The counter these assert against is the one thing that makes a leaked GPU
    # texture visible: nothing gets slower, nothing looks wrong, and video
    # memory fills up over an hour of play.

    it 'releases the upload once the image is collected' do
      before = live_textures

      described_class.new(app, path)

      expect(live_textures).to eq(before)
    end

    it 'keeps the upload alive while a tile of it still is' do
      before = live_textures

      tile = described_class.new(app, path).tile(2, 2, 0)

      expect(live_textures).to eq(before + 1)
      expect(tile.width).to eq(2) # and it is still usable, not a dangling view
    end

    it 'releases the upload only when the last view of it goes' do
      before = live_textures

      tiles = described_class.new(app, path).tiles(2, 2)
      tiles.pop
      expect(live_textures).to eq(before + 1)

      tiles.clear
      expect(live_textures).to eq(before)
    end

    it 'survives its app being collected first' do
      # Nothing orders a garbage collector's sweep, so both orders have to
      # work. The image keeps the app object reachable, which settles it here;
      # the C layer refcounts the app handle so the other order is safe too.
      before = live_textures

      images = Array.new(3) { described_class.new(app_that_goes_away, path) }

      expect(images.map(&:width)).to all(eq(4))
      images.clear
      expect(live_textures).to eq(before)
    end

    def app_that_goes_away
      RGame::Core::App.new(width: 100, height: 100, caption: 'transient')
    end
  end

  describe '#inspect' do
    it 'shows the size' do
      expect(described_class.new(app, path).inspect).to eq('#<RGame::Core::Image 4x2>')
    end
  end
end
