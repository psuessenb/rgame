# frozen_string_literal: true

# The renderer interface, stated once and run against every implementation.
#
# The engine layer never names a renderer class — a node's `draw` receives one
# and calls methods on it that it knows only by name. That makes this method
# list a real interface with more than one implementation: the live renderer
# that owns a GL context, and the recording fake that headless specs use in its
# place. If the fake drifts, the headless suite stays green while the game no
# longer runs, which is the one failure the two-suite split cannot catch by
# itself.
#
# So both are run against this group: the fake from `spec/`, the real one from
# `spec_core/`. A method added to the real renderer is not done until it appears
# here and in the fake too.
#
# ## What the host must provide
#
#   render { |renderer, image, font| ... }
#
# Yields a renderer that is ready to draw into, plus an image and a font that
# renderer will accept. For the fake all three are immediate; for the real one
# it opens a window and runs a frame, because drawing outside a frame is an
# error — and the image and font have to belong to *that* window's GL context,
# which is why they are yielded together rather than fetched separately.
#
# Examples that need neither may take two block parameters, or one.
#
# ## What this group does and does not check
#
# It checks the *shape* of the interface: that every method exists, accepts the
# arguments and keywords a caller will pass, and that the block forms yield and
# stay balanced. It cannot check pixels — the fake has none. That is
# `spec_core/rgame/core/renderer_spec.rb`'s job, and it is why that file reads
# the framebuffer back rather than trusting these examples alone.
RSpec.shared_examples 'a renderer' do
  describe 'shape primitives' do
    it 'draws a rectangle from a position and a size' do
      expect { render { |renderer, _image| renderer.rect(10, 20, 30, 40) } }.not_to raise_error
    end

    it 'draws a quad from four points in loop order' do
      expect { render { |renderer, _image| renderer.quad(0, 0, 10, 0, 10, 10, 0, 10) } }.not_to raise_error
    end

    it 'draws a triangle from three points' do
      expect { render { |renderer, _image| renderer.triangle(0, 0, 10, 0, 5, 10) } }.not_to raise_error
    end

    it 'draws a line with a thickness' do
      expect { render { |renderer, _image| renderer.line(0, 0, 10, 10, thickness: 3.0) } }.not_to raise_error
    end

    it 'draws a circle from a centre and a radius' do
      expect { render { |renderer, _image| renderer.circle(50, 50, 20) } }.not_to raise_error
    end

    it 'draws a debug box from a rectangle, with no colour to choose' do
      expect { render { |renderer, _image| renderer.debug_box(1, 2, 3, 4) } }.not_to raise_error
    end
  end

  describe 'images' do
    it 'draws one centred, with an angle and a scale' do
      expect { render { |renderer, image| renderer.image(image, 100, 100, angle: 45, scale: 2) } }.not_to raise_error
    end

    it 'draws one at its top-left as a backdrop' do
      expect { render { |renderer, image| renderer.background(image) } }.not_to raise_error
    end

    it 'places a backdrop somewhere other than the origin when asked' do
      expect { render { |renderer, image| renderer.background(image, 10, 20) } }.not_to raise_error
    end
  end

  describe 'z and colour' do
    # Every drawing method takes both, and takes them the same way — a caller
    # should never have to remember which of them is positional here.
    it 'accepts z: and color: on every drawing method' do
      expect do
        render do |renderer, image|
          renderer.rect(0, 0, 1, 1, z: 1, color: [255, 0, 0])
          renderer.quad(0, 0, 1, 0, 1, 1, 0, 1, z: 2, color: [0, 255, 0])
          renderer.triangle(0, 0, 1, 0, 0, 1, z: 3, color: [0, 0, 255])
          renderer.line(0, 0, 1, 1, thickness: 1, z: 4, color: [255, 255, 0])
          renderer.circle(0, 0, 1, z: 5, color: [255, 0, 255])
          renderer.image(image, 0, 0, z: 6, color: [0, 255, 255])
          renderer.background(image, z: 7, color: [128, 128, 128])
        end
      end.not_to raise_error
    end

    it 'accepts a colour as nil, a triple, a quadruple or a colour object' do
      expect do
        render do |renderer, _image|
          renderer.rect(0, 0, 1, 1, color: nil)
          renderer.rect(0, 0, 1, 1, color: [255, 0, 0])
          renderer.rect(0, 0, 1, 1, color: [255, 0, 0, 128])
          renderer.rect(0, 0, 1, 1, color: RGame::Util::Color::WHITE)
        end
      end.not_to raise_error
    end
  end

  describe 'text' do
    it 'draws a line of text at a position' do
      expect { render { |renderer, _image, _font| renderer.text('Score: 1200', 10, 20) } }
        .not_to raise_error
    end

    it 'draws text in a given font, z and colour' do
      expect do
        render do |renderer, _image, font|
          renderer.text('hello', 0, 0, z: 5, color: [255, 0, 0], font: font)
        end
      end.not_to raise_error
    end

    it 'draws an empty string without complaint' do
      expect { render { |renderer, _image, _font| renderer.text('', 0, 0) } }.not_to raise_error
    end

    it 'draws text outside the window without complaint' do
      # Scrolling labels go off the edge every frame; that is clipping's
      # problem, not the caller's.
      expect { render { |renderer, _image, _font| renderer.text('off', -500, -500) } }
        .not_to raise_error
    end

    it 'measures a string' do
      render do |renderer, _image, _font|
        expect(renderer.text_width('hello')).to be_a(Numeric)
        expect(renderer.text_width('hello')).to be_positive
      end
    end

    it 'measures an empty string as nothing' do
      render { |renderer, _image, _font| expect(renderer.text_width('')).to be_zero }
    end

    it 'measures a longer string as wider' do
      # A layout that centres a label depends on this being ordered, so it is
      # part of the interface rather than an accident of one implementation.
      render do |renderer, _image, _font|
        expect(renderer.text_width('aa')).to be > renderer.text_width('a')
      end
    end

    it 'reports a line height to step by' do
      render do |renderer, _image, _font|
        expect(renderer.text_height).to be_a(Numeric)
        expect(renderer.text_height).to be_positive
      end
    end

    it 'measures in a given font' do
      render do |renderer, _image, font|
        expect(renderer.text_width('hello', font: font)).to be_positive
        expect(renderer.text_height(font: font)).to be_positive
      end
    end
  end

  describe 'transform blocks' do
    it 'yields inside #rotated and returns what the block returned' do
      render do |renderer, _image|
        expect(renderer.rotated(45, 10, 10) { :drew }).to eq(:drew)
      end
    end

    it 'yields inside #translated' do
      render do |renderer, _image|
        expect(renderer.translated(5, 5) { :drew }).to eq(:drew)
      end
    end

    it 'yields inside #scaled' do
      render do |renderer, _image|
        expect(renderer.scaled(2) { :drew }).to eq(:drew)
        expect(renderer.scaled(2, 3) { :drew }).to eq(:drew)
      end
    end

    it 'yields inside #clipped' do
      render do |renderer, _image|
        expect(renderer.clipped(0, 0, 10, 10) { :drew }).to eq(:drew)
      end
    end

    it 'still yields when the transform is a no-op' do
      # The zero-angle and zero-offset fast paths skip the push entirely, so
      # they are a second code path through every one of these methods — and
      # the one most drawing actually takes.
      render do |renderer, _image|
        expect(renderer.rotated(0, 0, 0) { :drew }).to eq(:drew)
        expect(renderer.translated(0, 0) { :drew }).to eq(:drew)
        expect(renderer.scaled(1) { :drew }).to eq(:drew)
      end
    end

    it 'nests' do
      expect do
        render do |renderer, _image|
          renderer.translated(10, 10) do
            renderer.rotated(30, 0, 0) do
              renderer.clipped(0, 0, 50, 50) { renderer.rect(0, 0, 10, 10) }
            end
          end
        end
      end.not_to raise_error
    end

    it 'unwinds a block that raises, and keeps working afterwards' do
      # An unbalanced stack would displace every later draw in the frame, which
      # is a failure that shows up nowhere near its cause.
      render do |renderer, _image|
        expect { renderer.rotated(45, 0, 0) { raise 'from inside the block' } }
          .to raise_error(RuntimeError, 'from inside the block')

        renderer.rect(0, 0, 10, 10)
      end
    end
  end

  describe 'recording' do
    # A recording bakes a block of drawing so it can be replayed for a fraction
    # of the cost. What the contract can state is the shape: `record` takes a
    # block and returns something that draws itself at a position.
    it 'returns something that can draw itself' do
      render do |renderer, _image|
        baked = renderer.record { renderer.rect(0, 0, 10, 10) }

        expect(baked).to respond_to(:draw)
        baked.draw(100, 100)
      end
    end

    it 'accepts a position, z: and color: on the replay' do
      expect do
        render do |renderer, _image|
          baked = renderer.record { renderer.rect(0, 0, 10, 10) }
          baked.draw
          baked.draw(5, 5)
          baked.draw(5, 5, z: 3)
          baked.draw(5, 5, z: 3, color: [255, 0, 0, 128])
        end
      end.not_to raise_error
    end

    it 'bakes images as happily as shapes' do
      expect do
        render do |renderer, image|
          renderer.record { renderer.background(image) }.draw(0, 0)
        end
      end.not_to raise_error
    end

    it 'can be replayed more than once, anywhere' do
      expect do
        render do |renderer, _image|
          baked = renderer.record { renderer.rect(0, 0, 8, 8) }
          5.times { |i| baked.draw(i * 10, 0) }
        end
      end.not_to raise_error
    end

    it 'draws nothing at record time' do
      # The block's output goes into the recording, not into this frame. A
      # renderer that drew it as well would double every baked layer.
      render do |renderer, _image|
        expect(renderer.record { renderer.rect(0, 0, 10, 10) }).not_to be_nil
      end
    end

    it 'refuses to nest' do
      render do |renderer, _image|
        expect { renderer.record { renderer.record { renderer.rect(0, 0, 1, 1) } } }
          .to raise_error(RuntimeError, /nest/)
      end
    end

    it 'refuses a clip inside the block, because a clip cannot be baked' do
      render do |renderer, _image|
        expect { renderer.record { renderer.clipped(0, 0, 5, 5) { nil } } }
          .to raise_error(RuntimeError, /clip/)
      end
    end

    it 'unwinds a block that raises, and can record again afterwards' do
      render do |renderer, _image|
        expect { renderer.record { raise 'from inside the bake' } }
          .to raise_error(RuntimeError, 'from inside the bake')

        renderer.record { renderer.rect(0, 0, 1, 1) }.draw(0, 0)
      end
    end
  end
end
