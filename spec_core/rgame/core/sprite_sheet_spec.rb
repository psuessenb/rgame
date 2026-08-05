# frozen_string_literal: true

require 'json'

# Most of this runs against a StubImage and a FakeRenderer, with no window in
# sight: what a sprite sheet gets wrong is arithmetic — which cell a (row, col)
# lands on, where inside that cell the frame sits — and recorded calls state
# that far more precisely than a rendered frame could. Only `.load` needs the
# real thing, because only `.load` opens a file.
RSpec.describe RGame::Core::SpriteSheet do
  subject(:sheet) { described_class.new(image, descriptor) }

  let(:renderer) { FakeRenderer.new }

  # 4 columns x 2 rows of 16x16 cells.
  let(:image) { StubImage.new(64, 32) }
  let(:descriptor) { { frame_width: 16, frame_height: 16 } }

  # The image handed to the one recorded #image_at call.
  def drawn_frame = renderer.calls_to(:image_at).first.args.first

  describe '.new' do
    it 'reports the frame size' do
      expect([sheet.frame_width, sheet.frame_height]).to eq([16, 16])
    end

    it 'cuts the image into whole cells' do
      expect(sheet.grid).to eq([2, 4])
    end

    it 'hands back the animation table untouched' do
      # The scene layer builds its own animation state from this, so anything
      # this class did to the hash on the way through would be a surprise there.
      table = { walk_left: { row: 1, frames: 4, fps: 8 } }
      sheet = described_class.new(image, descriptor.merge(animations: table))

      expect(sheet.animations).to equal(table)
    end

    it 'has an empty animation table when the descriptor has none' do
      # A sheet of static tiles is a legitimate sheet; nil would make the scene
      # layer branch on it.
      expect(sheet.animations).to eq({})
    end

    it 'names a descriptor key it cannot do without' do
      # Without this the failure is a NoMethodError on nil from inside the
      # slicing arithmetic, which does not mention the file that is wrong.
      expect { described_class.new(image, frame_height: 16) }
        .to raise_error(ArgumentError, /frame_width/)
    end
  end

  describe 'the grid' do
    it 'takes each cell from its own row and column' do
      described_class.new(image, descriptor).draw(renderer, 1, 2, 0, 0)

      expect(drawn_frame.region).to eq([32, 16, 16, 16])
    end

    it 'lays cells out on cell_width, not frame_width' do
      # A frame narrower than its cell: the *stride* is still the cell, so
      # column 2 starts at 64 rather than at 2 x the frame width.
      wide_cells = { frame_width: 16, frame_height: 16, cell_width: 32, cell_height: 32 }
      described_class.new(StubImage.new(128, 64), wide_cells).draw(renderer, 1, 2, 0, 0)

      expect(drawn_frame.region).to eq([64, 32, 16, 16])
    end

    it 'offsets the frame inside its cell by the origin' do
      # This is what lets a sheet whose cells are sized for the widest pose
      # expose a tight, centred box for walking. Getting it wrong makes a
      # character drift sideways when its animation changes.
      offset = { frame_width: 16, frame_height: 24, cell_width: 32, cell_height: 32,
                 origin_x: 8, origin_y: 4 }
      described_class.new(StubImage.new(64, 32), offset).draw(renderer, 0, 1, 0, 0)

      expect(drawn_frame.region).to eq([40, 4, 16, 24])
    end

    it 'counts whole cells only, ignoring a partial trailing row' do
      # 70x32 is four whole 16px columns and six pixels of nothing.
      expect(described_class.new(StubImage.new(70, 32), descriptor).grid).to eq([2, 4])
    end
  end

  describe '#draw' do
    it 'places the frame by its top-left corner' do
      sheet.draw(renderer, 0, 0, 100, 50)

      expect(renderer.calls_to(:image_at).first.args[1..]).to eq([100, 50])
    end

    it 'passes the render layer through' do
      sheet.draw(renderer, 0, 0, 0, 0, z: 12)

      expect(renderer.calls_to(:image_at).first.options[:z]).to eq(12)
    end

    it 'draws unmirrored by default' do
      sheet.draw(renderer, 0, 0, 0, 0)

      expect(renderer.calls_to(:image_at).first.options[:scale_x]).to eq(1)
    end

    it 'mirrors on flip_x without moving the frame' do
      # The Gosu version added a frame width back to compensate for mirroring
      # about the anchor. Core mirrors inside the rectangle, so both facings
      # occupy the same pixels and there is nothing to compensate for — the
      # position here must be identical to the unflipped case above.
      sheet.draw(renderer, 0, 0, 100, 50, flip_x: true)

      call = renderer.calls_to(:image_at).first
      expect(call.args[1..]).to eq([100, 50])
      expect(call.options[:scale_x]).to eq(-1)
    end

    it 'draws exactly one frame' do
      sheet.draw(renderer, 1, 3, 0, 0)

      expect(renderer.calls.map(&:name)).to eq([:image_at])
    end
  end

  describe 'drawing a real sheet' do
    # StubImage proves the arithmetic; this proves the arithmetic reaches the
    # GPU. Four one-pixel columns, so a 2x2-frame sheet has two cells and each
    # cell has a distinguishable left and right — enough to catch both "drew the
    # wrong cell" and "drew it mirrored".
    let(:colours) do
      [[255, 0, 0, 255], [0, 0, 255, 255], [0, 255, 0, 255], [255, 255, 0, 255]]
    end
    let(:png) { PngFixture.write(4, 2) { |x, _y| colours[x] } }

    # Cell 1 is source columns 2..3 — green then yellow — drawn at 16x, so it
    # covers 0..32 on screen with the halves at 0..16 and 16..32.
    def second_cell(flip_x: false)
      RenderedFrame.capture(width: 64, height: 64) do |renderer, app|
        image = RGame::Core::Image.new(app, png)
        sheet = described_class.new(image, frame_width: 2, frame_height: 2)
        renderer.scaled(16) { sheet.draw(renderer, 0, 1, 0, 0, flip_x: flip_x) }
      end
    end

    it 'samples its own cell out of the sheet' do
      frame = second_cell

      expect(frame.about?(8, 8, [0, 255, 0, 255])).to be(true)
      expect(frame.about?(24, 8, [255, 255, 0, 255])).to be(true)
    end

    it 'mirrors that cell in place, and only that cell' do
      # The colours swap and the rectangle does not move. Were the mirror done
      # by flipping the whole sheet's coordinates instead of the frame's, this
      # would show cell 0's red and blue.
      frame = second_cell(flip_x: true)

      expect(frame.about?(8, 8, [255, 255, 0, 255])).to be(true)
      expect(frame.about?(24, 8, [0, 255, 0, 255])).to be(true)
    end
  end

  describe '.load' do
    let(:app) { RGame::Core::App.new(width: 64, height: 64, caption: 'sprite sheet spec') }

    # A 4x2 PNG plus a descriptor beside it, both in the fixture directory, so
    # the sibling-path resolution is exercised rather than assumed.
    def write_atlas(overrides = {})
      png = PngFixture.write(4, 2) { [255, 255, 255, 255] }
      atlas = { image: File.basename(png), frame_width: 2, frame_height: 2 }.merge(overrides)
      path = File.join(PngFixture.directory, "atlas_#{PngFixture.next_id}.json")
      File.write(path, JSON.generate(atlas))
      path
    end

    it 'parses the descriptor and loads the image beside it' do
      sheet = described_class.load(app, write_atlas)

      expect(sheet.frame_width).to eq(2)
      expect(sheet.grid).to eq([1, 2])
    end

    it 'resolves the image relative to the descriptor, not the process' do
      # The descriptor names 'fixture_4x2_N.png' with no directory, and the
      # working directory is the project root — so a load that resolved against
      # Dir.pwd would fail here rather than silently in someone's game.
      expect { described_class.load(app, write_atlas) }.not_to raise_error
    end

    it 'raises when the descriptor names an image that is not there' do
      expect { described_class.load(app, write_atlas(image: 'missing.png')) }
        .to raise_error(RGame::Core::Image::LoadError, /missing\.png/)
    end

    it 'raises when the descriptor itself is not there' do
      expect { described_class.load(app, '/no/such/atlas.json') }.to raise_error(Errno::ENOENT)
    end
  end
end
