# frozen_string_literal: true

# Entirely against StubImage and FakeRenderer, and this is the class that gains
# most from that: what a nine-slice gets wrong is a rectangle — a band one tile
# too wide, a corner at the wrong end, a tile drawn outside the clip that was
# supposed to crop it. A recorded call says exactly which rectangle; a rendered
# frame would only say "the panel looks a bit off".
RSpec.describe RGame::Core::NineSlice do
  let(:renderer) { FakeRenderer.new }

  # A 12x12 source with 4-pixel borders, so every piece is 4x4 and a scale of 1
  # makes the arithmetic readable: corners at the corners, bands of 4.
  let(:image) { StubImage.new(12, 12) }

  def slice(scale: 1, border: 4, image: self.image, w: 12, h: 12)
    described_class.new(image, x: 0, y: 0, w: w, h: h, border: border, scale: scale)
  end

  # Every image_at call as [region, x, y], in the order they were made.
  def placements
    renderer.calls_to(:image_at).map { |call| [call.args[0].region, call.args[1], call.args[2]] }
  end

  def placements_at(region) = placements.select { |r, _x, _y| r == region }.map { |_r, x, y| [x, y] }

  # The nine source rectangles of the default slice, by name. Methods rather
  # than constants: a constant declared inside an example group leaks onto
  # Object for the whole run.
  def tl = [0, 0, 4, 4]
  def tr = [8, 0, 4, 4]
  def bl = [0, 8, 4, 4]
  def br = [8, 8, 4, 4]
  def top = [4, 0, 4, 4]
  def bottom = [4, 8, 4, 4]
  def left = [0, 4, 4, 4]
  def right = [8, 4, 4, 4]
  def centre = [4, 4, 4, 4]

  describe 'cutting' do
    it 'takes the four corners from the four corners of the source rect' do
      slice.draw(renderer, 0, 0, 12, 12)

      expect(placements_at(tl)).to eq([[0, 0]])
      expect(placements_at(tr)).to eq([[8, 0]])
      expect(placements_at(bl)).to eq([[0, 8]])
      expect(placements_at(br)).to eq([[8, 8]])
    end

    it 'reads its source rect from wherever it sits on a shared sheet' do
      # UiAtlas puts many of these on one image, so a piece must be cut relative
      # to (x, y) rather than to the image's own origin.
      described_class.new(StubImage.new(64, 64), x: 20, y: 30, w: 12, h: 12, border: 4)
                     .draw(renderer, 0, 0, 12, 12)

      expect(placements_at([20, 30, 4, 4])).to eq([[0, 0]])
    end

    it 'accepts a uniform integer border' do
      expect { slice(border: 4) }.not_to raise_error
    end

    it 'accepts a border given per side' do
      described_class.new(image, x: 0, y: 0, w: 12, h: 12,
                                 border: { left: 2, right: 6, top: 4, bottom: 4 })
                     .draw(renderer, 0, 0, 12, 12)

      expect(placements_at([0, 0, 2, 4])).to eq([[0, 0]])   # narrow top-left
      expect(placements_at([6, 0, 6, 4])).to eq([[6, 0]])   # wide top-right
    end

    it 'refuses borders that do not fit the source rect' do
      # The old layer let this through and produced degenerate sub-images; here
      # it is a message that names both the borders and the rect.
      expect { slice(border: 8) }
        .to raise_error(ArgumentError, /borders .* do not fit in a 12x12 rect/)
    end

    it 'refuses a scale that would never advance the tiling loop' do
      expect { slice(scale: 0) }.to raise_error(ArgumentError, /scale must be positive/)
    end

    it 'allows a slice with no centre column at all' do
      # left 4 + right 4 in an 8-wide rect: a bar that stretches only
      # vertically. The zero-width pieces are simply never cut — asking
      # Image#subimage for one would raise.
      expect { slice(image: StubImage.new(8, 12), w: 8).draw(renderer, 0, 0, 8, 40) }
        .not_to raise_error
    end
  end

  describe 'tiling' do
    it 'repeats the top edge across the inner width' do
      # Inner width 12 with a 4-wide tile: three across, at 4, 8 and 12.
      slice.draw(renderer, 0, 0, 20, 12)

      expect(placements_at(top)).to eq([[4, 0], [8, 0], [12, 0]])
    end

    it 'runs the bottom edge along the bottom, not the top' do
      # The five band() calls differ only in which offsets they pass, which is
      # exactly the shape a copy-paste gets wrong.
      slice.draw(renderer, 0, 0, 20, 12)

      expect(placements_at(bottom)).to eq([[4, 8], [8, 8], [12, 8]])
    end

    it 'repeats the left edge down the inner height' do
      slice.draw(renderer, 0, 0, 12, 20)

      expect(placements_at(left)).to eq([[0, 4], [0, 8], [0, 12]])
    end

    it 'runs the right edge down the right-hand side' do
      slice.draw(renderer, 0, 0, 12, 20)

      expect(placements_at(right)).to eq([[8, 4], [8, 8], [8, 12]])
    end

    it 'repeats the centre in both directions' do
      slice.draw(renderer, 0, 0, 20, 20)

      expect(placements_at(centre)).to eq([[4, 4], [8, 4], [12, 4],
                                           [4, 8], [8, 8], [12, 8],
                                           [4, 12], [8, 12], [12, 12]])
    end

    it 'starts one more tile rather than leaving a gap' do
      # Inner width 6 does not divide by 4: two tiles, the second overhanging,
      # and the clip below is what crops it. A loop that stopped short would
      # leave two pixels of nothing at the seam.
      slice.draw(renderer, 0, 0, 14, 12)

      expect(placements_at(top)).to eq([[4, 0], [8, 0]])
    end

    it 'clips every band to itself' do
      slice.draw(renderer, 0, 0, 14, 12)

      # Named `tile` rather than `top`: assigning to `top` here would make the
      # block's `top` a nil local instead of the method above.
      tile = renderer.calls_to(:image_at).find { |call| call.args[0].region == top }
      expect(tile.transforms.map(&:name)).to eq([:clipped])
      expect(tile.transforms.first.args).to eq([4, 0, 6, 4])
    end

    it 'closes each band before opening the next' do
      # Bands are siblings, not nested: a tile is inside exactly one clip. Were
      # they nested, the intersection would shrink to nothing by the third band
      # and half the panel would vanish.
      slice.draw(renderer, 0, 0, 20, 20)

      expect(renderer.calls_to(:image_at).map(&:depth).uniq).to eq([1, 0])
    end

    it 'draws the corners after the bands' do
      # Same z, so submission order decides what is on top. A tile that reached
      # the edge of its band would otherwise show through the transparent
      # pixels of the corner beside it.
      slice.draw(renderer, 0, 0, 20, 20)

      corners = [tl, tr, bl, br]
      first_corner = placements.index { |region, _x, _y| corners.include?(region) }
      last_band = placements.rindex { |region, _x, _y| !corners.include?(region) }

      expect(first_corner).to be > last_band
    end

    it 'leaves the corners outside any clip' do
      slice.draw(renderer, 0, 0, 20, 20)

      corner = renderer.calls_to(:image_at).find { |call| call.args[0].region == tl }
      expect(corner.depth).to be_zero
    end
  end

  describe 'scale' do
    it 'multiplies both the piece size and the step between tiles' do
      # At 3x a 4-pixel tile occupies 12 screen pixels, so the second one starts
      # at 12 past the first, not at 4.
      slice(scale: 3).draw(renderer, 0, 0, 60, 12)

      expect(placements_at(top).first(2)).to eq([[12, 0], [24, 0]])
      expect(renderer.calls_to(:image_at).first.options[:scale_x]).to eq(3)
    end

    it 'places the far corners a scaled border in from the far edge' do
      slice(scale: 3).draw(renderer, 0, 0, 60, 60)

      expect(placements_at(tr)).to eq([[48, 0]])
      expect(placements_at(br)).to eq([[48, 48]])
    end
  end

  describe 'a rectangle smaller than its own borders' do
    it 'draws the corners and no bands' do
      # 8x8 with 4-pixel borders on every side: the inner region is negative, so
      # a naive subtraction would ask for bands of negative size.
      slice.draw(renderer, 0, 0, 8, 8)

      expect(placements_at(tl)).to eq([[0, 0]])
      expect(placements_at(centre)).to be_empty
      expect(placements_at(top)).to be_empty
    end
  end

  describe 'z and colour' do
    it 'draws every piece at the z it was given' do
      slice.draw(renderer, 0, 0, 20, 20, z: 7)

      expect(renderer.calls_to(:image_at).map { |call| call.options[:z] }.uniq).to eq([7])
    end

    it 'tints every piece, bands included' do
      # A focus highlight has to reach the whole widget; tinting only the
      # corners is a bug that reads as a rendering artefact.
      slice.draw(renderer, 0, 0, 20, 20, color: [255, 0, 0])

      expect(renderer.calls_to(:image_at).map { |call| call.options[:color] }.uniq)
        .to eq([[255, 0, 0]])
    end
  end

  describe 'drawing a real slice' do
    # The stub proves the arithmetic; this proves it reaches the GPU. A 3x3
    # source with a 1-pixel border: red corners, green edges, blue centre.
    let(:png) do
      PngFixture.write(3, 3) do |x, y|
        edge_x = x != 1
        edge_y = y != 1
        if edge_x && edge_y then [255, 0, 0, 255]
        elsif edge_x || edge_y then [0, 255, 0, 255]
        else [0, 0, 255, 255]
        end
      end
    end

    it 'puts corners at the corners and the centre in the middle' do
      frame = RenderedFrame.capture(width: 64, height: 64) do |renderer, app|
        image = RGame::Core::Image.new(app, png)
        panel = described_class.new(image, x: 0, y: 0, w: 3, h: 3, border: 1, scale: 8)
        panel.draw(renderer, 0, 0, 64, 64)
      end

      expect(frame.about?(4, 4, [255, 0, 0, 255])).to be(true)    # top-left corner
      expect(frame.about?(60, 60, [255, 0, 0, 255])).to be(true)  # bottom-right corner
      expect(frame.about?(32, 4, [0, 255, 0, 255])).to be(true)   # top edge
      expect(frame.about?(4, 32, [0, 255, 0, 255])).to be(true)   # left edge
      expect(frame.about?(32, 32, [0, 0, 255, 255])).to be(true)  # centre
    end
  end
end
