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

    it 'stops #tiles at count:' do
      expect(sheet.tiles(2, 2, count: 4).size).to eq(4)
    end

    it 'refuses a count: the sheet does not hold' do
      expect { sheet.tiles(2, 2, count: 7) }.to raise_error(IndexError, /6 tiles of 2x2/)
    end
  end

  # A sheet cut with a margin and spacing, read back through a real frame: the
  # size of a tile says nothing about which pixels it was cut from.
  describe 'translucent pixels' do
    # A half-transparent pixel drawn over white, at eight times its size. The
    # engine premultiplies the file's pixels as it loads them, and must draw what
    # straight blending drew, within 1 per channel.
    it 'draws a half-transparent pixel as straight blending does' do
      pixel = PngFixture.write(1, 1) { [200, 100, 50, 128] }
      frame = RenderedFrame.capture(width: 16, height: 16) do |renderer, app|
        renderer.rect(0, 0, 16, 16, color: RGame::Util::Color::WHITE)
        renderer.image_at(described_class.new(app, pixel), 0, 0, scale_x: 8, scale_y: 8)
      end
      expected = [200, 100, 50].map { ((it * 128) + (255 * 127)) / 255.0 }

      expect(frame.at(4, 4).first(3)).to match(expected.map { a_value_within(1).of(it) })
    end

    it 'draws nothing for a fully transparent pixel, whatever colour it stored' do
      pixel = PngFixture.write(1, 1) { [255, 255, 255, 0] }
      frame = RenderedFrame.capture(width: 16, height: 16) do |renderer, app|
        renderer.rect(0, 0, 16, 16, color: RGame::Util::Color::BLACK)
        renderer.image_at(described_class.new(app, pixel), 0, 0, scale_x: 8, scale_y: 8)
      end

      expect(frame.at(4, 4).first(3)).to eq([0, 0, 0])
    end
  end

  describe 'filtering' do
    # One black and one white pixel, side by side, drawn eight times their size:
    # the middle row of what comes back, as red values.
    def black_then_white(texture_filter)
      path = PngFixture.write(2, 1) { |x, _y| x.zero? ? [0, 0, 0, 255] : [255, 255, 255, 255] }
      frame = RenderedFrame.capture(width: 16, height: 8, texture_filter:) do |renderer, app|
        renderer.image_at(described_class.new(app, path), 0, 0, scale_x: 8, scale_y: 8)
      end
      Array.new(16) { frame.at(it, 4)[0] }
    end

    it 'draws only the pixels the image holds under :nearest' do
      expect(black_then_white(:nearest)).to eq([0] * 8 + [255] * 8)
    end

    it 'blends neighbouring pixels under :linear' do
      row = black_then_white(:linear)

      expect([row.first, row.last]).to eq([0, 255])
      expect(row[7..8]).to all(be_between(60, 195))
    end

    it 'keeps a tile of a :linear sheet from sampling the tile beside it' do
      # Tile 0 is red and tile 1 blue. Drawn at 3.5 times, the tile's right
      # edge would blend in blue unless its UVs stop half a texel short.
      sheet = PngFixture.write(8, 4) { |x, _y| x < 4 ? [255, 0, 0, 255] : [0, 0, 255, 255] }
      frame = RenderedFrame.capture(width: 14, height: 14, texture_filter: :linear) do |renderer, app|
        renderer.image_at(described_class.new(app, sheet).tile(4, 4, 0), 0, 0, scale_x: 3.5, scale_y: 3.5)
      end
      pixels = (0...14).to_a.product((0...14).to_a).map { |x, y| frame.at(x, y).first(3) }

      expect(pixels.uniq).to eq([[255, 0, 0]])
    end

    # **The plan's acceptance test: premultiplied alpha and linear filtering
    # together.** A white disc with an anti-aliased edge, on transparent black,
    # drawn at 2.5 times over white and over black. Straight alpha would filter
    # the edge towards the black around it, and draw a grey ring over white.
    it 'draws an anti-aliased edge with no dark fringe under :linear' do
      disc = PngFixture.write(16, 16) do |x, y|
        coverage = (6.5 - Math.hypot(x + 0.5 - 8, y + 0.5 - 8)).clamp(0.0, 1.0)
        coverage.zero? ? [0, 0, 0, 0] : [255, 255, 255, (coverage * 255).round]
      end
      frame = RenderedFrame.capture(width: 88, height: 40, texture_filter: :linear) do |renderer, app|
        image = described_class.new(app, disc)
        renderer.rect(0, 0, 40, 40, color: RGame::Util::Color::WHITE)
        renderer.rect(48, 0, 40, 40, color: RGame::Util::Color::BLACK)
        renderer.image_at(image, 0, 0, scale_x: 2.5, scale_y: 2.5)
        renderer.image_at(image, 48, 0, scale_x: 2.5, scale_y: 2.5)
      end
      over_white = (0...40).to_a.product((0...40).to_a).map { |x, y| frame.at(x, y).first(3).min }
      over_black = (0...40).map { |x| frame.at(48 + x, 20)[0] }

      expect(over_white.min).to be >= 254
      expect([over_black.first, over_black[20]]).to eq([0, 255])
      expect(over_black).to include(be_between(20, 235))
    end
  end

  describe 'tiles with a margin and spacing' do
    # Three columns and two rows of 2x2 tiles, with a 1 px margin and 1 px of
    # spacing. Tile n is filled with the grey value 40 * (n + 1), and every
    # pixel of margin and spacing is red, so a tile cut one pixel off shows it.
    def sheet_path
      PngFixture.write(10, 7) do |x, y|
        col, x_in = (x - 1).divmod(3)
        row, y_in = (y - 1).divmod(3)
        next [255, 0, 0, 255] if x.zero? || y.zero? || x_in == 2 || y_in == 2 || col > 2 || row > 1

        grey = 40 * ((row * 3) + col + 1)
        [grey, grey, grey, 255]
      end
    end

    # Each tile drawn at (4 * index, 0) at twice its size, and every pixel of
    # each read back.
    def drawn_tiles(**)
      frame = RenderedFrame.capture(width: 32, height: 8) do |renderer, app|
        described_class.new(app, sheet_path).tiles(2, 2, **).each_with_index do |tile, index|
          renderer.image_at(tile, index * 4, 0, scale_x: 2, scale_y: 2)
        end
      end
      Array.new(6) { |index| Array.new(16) { frame.at((index * 4) + (it % 4), it / 4)[0] }.uniq }
    end

    it 'cuts every tile from inside its margin and spacing' do
      expect(drawn_tiles(margin: 1, spacing: 1)).to eq([[40], [80], [120], [160], [200], [240]])
    end

    it 'counts the columns and rows that fit when neither is given' do
      expect(described_class.new(app, sheet_path).tiles(2, 2, margin: 1, spacing: 1).size).to eq(6)
    end

    it 'lays the tiles out by columns: when given' do
      # Two columns rather than the three that fit, so tile 2 is the first of
      # the second row.
      expect(drawn_tiles(margin: 1, spacing: 1, columns: 2, count: 4).first(4))
        .to eq([[40], [80], [160], [200]])
    end

    it 'refuses a tile that would reach outside the sheet' do
      expect { described_class.new(app, sheet_path).tiles(2, 2, margin: 1, spacing: 1, count: 9) }
        .to raise_error(ArgumentError, /does not fit in a 10x7 image/)
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
