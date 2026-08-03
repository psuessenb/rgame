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
#   render { |renderer, image| ... }
#
# Yields a renderer that is ready to draw into, plus an image that renderer will
# accept. For the fake both are immediate; for the real one it opens a window
# and runs a frame, because drawing outside a frame is an error — and the image
# has to be uploaded into *that* window's GL context, which is why the two are
# yielded together rather than fetched separately.
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
end
