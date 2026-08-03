# frozen_string_literal: true

RSpec.describe RGame::Core::Renderer do
  # The clear colour, as it comes back out of the framebuffer — "nothing was
  # drawn here" in the pixel assertions below.
  def background = [26, 26, 38, 255]

  let(:app) { RGame::Core::App.new(width: 64, height: 64, caption: 'renderer spec') }

  describe 'the renderer interface' do
    # The real implementation, run against the same contract as the recording
    # fake in spec/. Between them that is the whole guarantee that a headless
    # green suite still predicts whether the game runs.
    # The image is built from the capture's own app: a texture belongs to one GL
    # context, so one made anywhere else could not be drawn here.
    def render
      RenderedFrame.capture(width: 64, height: 64) do |renderer, app|
        yield(renderer, RGame::Core::Image.new(app, white_png))
      end
    end

    def white_png = @white_png ||= PngFixture.write(4, 4) { [255, 255, 255, 255] }

    it_behaves_like 'a renderer'
  end

  describe '.new' do
    it 'refuses anything that is not an App' do
      expect { described_class.new(Object.new) }.to raise_error(TypeError)
    end
  end

  describe 'drawing outside a frame' do
    # The canvas would take the vertices and drop them at the next frame's
    # begin — a call that does nothing, reports nothing, and leaves nothing to
    # search for. Refusing is the whole point.
    it 'raises rather than silently drawing nothing' do
      renderer = described_class.new(app)

      expect { renderer.rect(0, 0, 10, 10) }
        .to raise_error(RuntimeError, /only allowed inside #draw/)
    end

    it 'reports whether a frame is open' do
      renderer = described_class.new(app)
      expect(renderer.drawing?).to be(false)

      inside = nil
      RenderedFrame.capture(width: 16, height: 16) { |r, _app| inside = r.drawing? }
      expect(inside).to be(true)
    end
  end

  describe 'an image from another App' do
    it 'raises rather than drawing a blank white quad' do
      # A GL texture belongs to one context and is not shared with another, so
      # this would otherwise sample nothing: no GL error, no log line, just a
      # white rectangle where the sprite should be. It was a real failure in
      # these very specs before the check existed.
      other = RGame::Core::App.new(width: 8, height: 8, caption: 'elsewhere')
      foreign = RGame::Core::Image.new(other, PngFixture.write(2, 2) { [255, 255, 255, 255] })

      expect do
        RenderedFrame.capture(width: 16, height: 16) do |renderer, _app|
          renderer.background(foreign)
        end
      end.to raise_error(ArgumentError, /different App/)
    end
  end

  describe 'what reaches the framebuffer' do
    it 'puts a rectangle where it was asked for, in the colour asked for' do
      frame = RenderedFrame.capture(width: 64, height: 64) do |renderer, _app|
        renderer.rect(10, 10, 20, 20, color: [255, 0, 0])
      end

      expect(frame.about?(20, 20, [255, 0, 0, 255])).to be(true)
      # ...and nowhere else. A y-flipped projection would put it at the bottom
      # and pass the first assertion of a centred shape.
      expect(frame.about?(20, 50, background)).to be(true)
      expect(frame.about?(50, 20, background)).to be(true)
    end

    it 'measures y downwards from the top-left' do
      frame = RenderedFrame.capture(width: 64, height: 64) do |renderer, _app|
        renderer.rect(0, 0, 64, 8, color: [0, 255, 0])
      end

      expect(frame.about?(32, 4, [0, 255, 0, 255])).to be(true)
      expect(frame.about?(32, 60, background)).to be(true)
    end

    it 'draws a circle round, filling its centre and missing its corners' do
      frame = RenderedFrame.capture(width: 64, height: 64) do |renderer, _app|
        renderer.circle(32, 32, 20, color: [255, 255, 0])
      end

      expect(frame.about?(32, 32, [255, 255, 0, 255])).to be(true)
      expect(frame.about?(32, 15, [255, 255, 0, 255])).to be(true) # inside, near the top
      expect(frame.about?(17, 17, background)).to be(true)         # the corner of its bounds
    end

    it 'gives a line real thickness' do
      frame = RenderedFrame.capture(width: 64, height: 64) do |renderer, _app|
        renderer.line(0, 32, 64, 32, thickness: 8, color: [255, 0, 255])
      end

      expect(frame.about?(32, 32, [255, 0, 255, 255])).to be(true)
      expect(frame.about?(32, 29, [255, 0, 255, 255])).to be(true)
      expect(frame.about?(32, 20, background)).to be(true)
    end
  end

  describe 'z ordering' do
    it 'puts a higher z on top regardless of the order calls were made' do
      frame = RenderedFrame.capture(width: 64, height: 64) do |renderer, _app|
        renderer.rect(0, 0, 64, 64, z: 10, color: [0, 0, 255])
        renderer.rect(0, 0, 64, 64, z: 1, color: [255, 0, 0])
      end

      # Blue was drawn first but has the higher z, so blue wins.
      expect(frame.about?(32, 32, [0, 0, 255, 255])).to be(true)
    end

    it 'keeps call order among equal z' do
      frame = RenderedFrame.capture(width: 64, height: 64) do |renderer, _app|
        renderer.rect(0, 0, 64, 64, z: 5, color: [255, 0, 0])
        renderer.rect(0, 0, 64, 64, z: 5, color: [0, 0, 255])
      end

      expect(frame.about?(32, 32, [0, 0, 255, 255])).to be(true)
    end

    it 'defaults shapes above images' do
      # Not an arbitrary default: a debug box or a health bar drawn without a
      # z: has to land on top of the scene, not under it.
      green = PngFixture.write(64, 64) { [0, 255, 0, 255] }
      frame = RenderedFrame.capture(width: 64, height: 64) do |renderer, app|
        renderer.rect(0, 0, 64, 64, color: [255, 0, 0])
        renderer.background(RGame::Core::Image.new(app, green))
      end

      expect(frame.about?(32, 32, [255, 0, 0, 255])).to be(true)
    end
  end

  describe 'alpha' do
    it 'blends a translucent colour over what is beneath it' do
      # Depth testing would break this: a translucent pixel that writes depth
      # discards whatever should have shown through. The CPU z-sort exists so
      # that blending can be on.
      frame = RenderedFrame.capture(width: 64, height: 64) do |renderer, _app|
        renderer.rect(0, 0, 64, 64, z: 1, color: [0, 0, 0])
        renderer.rect(0, 0, 64, 64, z: 2, color: [255, 255, 255, 128])
      end

      red, green, blue, = frame.at(32, 32)
      expect([red, green, blue]).to all(be_between(100, 155))
    end
  end

  describe 'clipping' do
    it 'confines drawing to the clip rectangle' do
      frame = RenderedFrame.capture(width: 64, height: 64) do |renderer, _app|
        renderer.clipped(0, 0, 32, 32) do
          renderer.rect(0, 0, 64, 64, color: [255, 0, 0])
        end
      end

      expect(frame.about?(16, 16, [255, 0, 0, 255])).to be(true)
      # The scissor box is measured from the bottom in GL and from the top
      # here; without the flip this rectangle clips the wrong half, which on a
      # centred shape looks entirely correct.
      expect(frame.about?(48, 48, background)).to be(true)
      expect(frame.about?(48, 16, background)).to be(true)
      expect(frame.about?(16, 48, background)).to be(true)
    end

    it 'narrows when clips nest, never widens' do
      frame = RenderedFrame.capture(width: 64, height: 64) do |renderer, _app|
        renderer.clipped(0, 0, 32, 64) do
          renderer.clipped(0, 0, 64, 32) do
            renderer.rect(0, 0, 64, 64, color: [255, 0, 0])
          end
        end
      end

      expect(frame.about?(16, 16, [255, 0, 0, 255])).to be(true)
      expect(frame.about?(48, 16, background)).to be(true)
      expect(frame.about?(16, 48, background)).to be(true)
    end

    it 'releases the clip after the block' do
      frame = RenderedFrame.capture(width: 64, height: 64) do |renderer, _app|
        renderer.clipped(0, 0, 8, 8) { renderer.rect(0, 0, 4, 4, color: [0, 255, 0]) }
        renderer.rect(40, 40, 16, 16, color: [255, 0, 0])
      end

      expect(frame.about?(48, 48, [255, 0, 0, 255])).to be(true)
    end

    it 'gives each viewport its own region, which is what split-screen is' do
      frame = RenderedFrame.capture(width: 64, height: 64) do |renderer, _app|
        renderer.clipped(0, 0, 32, 64) do
          renderer.translated(0, 0) { renderer.rect(0, 0, 64, 64, color: [255, 0, 0]) }
        end
        renderer.clipped(32, 0, 32, 64) do
          renderer.translated(32, 0) { renderer.rect(0, 0, 64, 64, color: [0, 0, 255]) }
        end
      end

      expect(frame.about?(16, 32, [255, 0, 0, 255])).to be(true)
      expect(frame.about?(48, 32, [0, 0, 255, 255])).to be(true)
    end
  end

  describe 'transforms' do
    it 'moves what is drawn inside #translated' do
      frame = RenderedFrame.capture(width: 64, height: 64) do |renderer, _app|
        renderer.translated(32, 32) { renderer.rect(0, 0, 8, 8, color: [255, 0, 0]) }
      end

      expect(frame.about?(36, 36, [255, 0, 0, 255])).to be(true)
      expect(frame.about?(4, 4, background)).to be(true)
    end

    it 'turns a positive angle clockwise on screen' do
      # The convention measured against the layer being replaced. A shape to the
      # right of the pivot ends up below it, because screen y points down.
      frame = RenderedFrame.capture(width: 64, height: 64) do |renderer, _app|
        renderer.rotated(90, 32, 32) do
          renderer.rect(40, 28, 16, 8, color: [255, 0, 0]) # to the right of the pivot
        end
      end

      expect(frame.about?(32, 44, [255, 0, 0, 255])).to be(true) # now below it
      expect(frame.about?(44, 32, background)).to be(true)
    end

    it 'grows what is drawn inside #scaled' do
      frame = RenderedFrame.capture(width: 64, height: 64) do |renderer, _app|
        renderer.scaled(4) { renderer.rect(0, 0, 8, 8, color: [255, 0, 0]) }
      end

      expect(frame.about?(28, 28, [255, 0, 0, 255])).to be(true)
      expect(frame.about?(36, 36, background)).to be(true)
    end

    it 'restores the transform after the block' do
      frame = RenderedFrame.capture(width: 64, height: 64) do |renderer, _app|
        renderer.translated(32, 32) { renderer.rect(0, 0, 4, 4, color: [0, 255, 0]) }
        renderer.rect(0, 0, 8, 8, color: [255, 0, 0])
      end

      expect(frame.about?(4, 4, [255, 0, 0, 255])).to be(true)
    end
  end

  describe 'images' do
    # Two rows, red on top of blue: an image that can tell you which way up it
    # was drawn. Everything below this point was unverifiable until there was
    # something to draw a texture with.
    let(:striped_png) do
      PngFixture.write(2, 2) { |_x, y| y.zero? ? [255, 0, 0, 255] : [0, 0, 255, 255] }
    end

    # Each capture uploads the fixture into its own window's context.
    def with_striped
      RenderedFrame.capture(width: 64, height: 64) do |renderer, app|
        yield(renderer, RGame::Core::Image.new(app, striped_png))
      end
    end

    it 'draws the decoded pixels the right way up' do
      # The upload sends stb's rows in order, top first, and the UVs put row 0
      # at v = 0. If either flipped, this image would be blue over red.
      frame = with_striped { |renderer, image| renderer.scaled(16) { renderer.background(image) } }

      # Scaled 16x, the 2x2 image covers 0..32: red rows on top, blue below.
      expect(frame.about?(16, 8, [255, 0, 0, 255])).to be(true)
      expect(frame.about?(16, 24, [0, 0, 255, 255])).to be(true)
    end

    it 'draws a backdrop from its top-left corner' do
      frame = with_striped { |renderer, image| renderer.scaled(8) { renderer.background(image) } }

      expect(frame.about?(1, 1, [255, 0, 0, 255])).to be(true)
      expect(frame.about?(20, 20, background)).to be(true)
    end

    it 'centres #image on the position it is given' do
      frame = with_striped { |renderer, image| renderer.image(image, 32, 32, scale: 16) }

      expect(frame.about?(32, 24, [255, 0, 0, 255])).to be(true)
      expect(frame.about?(32, 40, [0, 0, 255, 255])).to be(true)
      expect(frame.about?(2, 2, background)).to be(true)
    end

    it 'rotates an image clockwise about its centre' do
      # Turned 90 degrees clockwise, the red row that was on top is now on the
      # right-hand side.
      frame = with_striped { |renderer, image| renderer.image(image, 32, 32, angle: 90, scale: 16) }

      expect(frame.about?(40, 32, [255, 0, 0, 255])).to be(true)
      expect(frame.about?(24, 32, [0, 0, 255, 255])).to be(true)
    end

    it 'tints an image by the colour given' do
      white = PngFixture.write(2, 2) { [255, 255, 255, 255] }
      frame = RenderedFrame.capture(width: 64, height: 64) do |renderer, app|
        image = RGame::Core::Image.new(app, white)
        renderer.scaled(32) { renderer.background(image, color: [255, 0, 0]) }
      end

      expect(frame.about?(32, 32, [255, 0, 0, 255])).to be(true)
    end

    it 'samples only its own tile out of a sheet' do
      # The failure this catches is a UV normalised against the tile instead of
      # the sheet, which draws the whole sheet into every tile.
      png = PngFixture.write(2, 2) { |x, y| x.zero? && y.zero? ? [255, 0, 0, 255] : [0, 0, 255, 255] }

      frame = RenderedFrame.capture(width: 64, height: 64) do |renderer, app|
        corner = RGame::Core::Image.new(app, png).subimage(0, 0, 1, 1)
        renderer.scaled(64) { renderer.background(corner) }
      end

      expect(frame.about?(8, 8, [255, 0, 0, 255])).to be(true)
      expect(frame.about?(56, 56, [255, 0, 0, 255])).to be(true)
    end
  end
end
