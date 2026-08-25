# frozen_string_literal: true

require 'fiddle'

# Draws one frame through a real window and reads the result back.
#
#   frame = RenderedFrame.capture(width: 64, height: 64) do |renderer, app|
#     renderer.rect(0, 0, 32, 32, color: [255, 0, 0])
#   end
#
#   frame.at(10, 10)   # => [255, 0, 0, 255]
#
# The block is handed the app as well as the renderer, because an image has to
# be uploaded into the GL context it will be drawn in — one made from any other
# app draws a plain white quad, and the renderer now says so rather than letting
# that happen.
#
# This is the tier that catches what nothing above it can. Everything from a
# call to a batch is arithmetic and is Check-tested with no display; what is
# left is whether the GL shim then puts the pixels in the right place — the
# projection's y direction, the scissor's y flip, whether blending is on,
# whether the z-sort survives the trip to the GPU. Three pixel reads catch more
# of that than any amount of staring at code.
#
# ## How the read is possible at all
#
# Drawing is deferred: a `draw` call only appends to a queue, which is sorted,
# batched and submitted to GL only once the callback returns — so there is
# nothing to read yet at the point `draw` itself returns. `App#frame_end` is
# the hook that exists for exactly this: the engine calls it once submission
# has happened but before `SDL_GL_SwapWindow`, which is the one moment the back
# buffer is guaranteed to hold this frame's image on every driver. Reading
# there needs no assumption about how a given driver implements the swap.
# Reading at the *start of the next frame* instead would rely on the swap being
# a copy rather than a page flip — true of Mesa's llvmpipe under Xvfb, and false
# of real GPU drivers, which are free to page-flip and leave the back buffer
# undefined at that moment.
module RenderedFrame
  GL_RGBA = 0x1908
  GL_UNSIGNED_BYTE = 0x1401
  GL_BACK = 0x0405

  class << self
    # Runs `block` inside one real frame and returns the pixels it produced. The
    # block receives the renderer and the app it belongs to.
    def capture(width:, height:, &block)
      app = capture_class.new(width, height, block)
      app.run
      app.frame
    end

    # The GL entry points, resolved once. Fiddle calls into the already-loaded
    # libGL rather than adding a dependency — the process has one open because
    # the window does.
    def read_pixels
      @read_pixels ||= Fiddle::Function.new(
        library['glReadPixels'],
        ([Fiddle::TYPE_INT] * 6) + [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID
      )
    end

    def read_buffer
      @read_buffer ||= Fiddle::Function.new(library['glReadBuffer'], [Fiddle::TYPE_INT],
                                            Fiddle::TYPE_VOID)
    end

    def finish
      @finish ||= Fiddle::Function.new(library['glFinish'], [], Fiddle::TYPE_VOID)
    end

    # The library name SDL's own GL context already loaded — this reaches into
    # it rather than opening a second copy, so the name has to match whatever
    # that platform's loader actually calls it.
    def library
      @library ||= Fiddle.dlopen(
        case RbConfig::CONFIG['host_os']
        when /darwin/ then '/System/Library/Frameworks/OpenGL.framework/OpenGL'
        when /mswin|mingw|cygwin/ then 'opengl32.dll'
        else 'libGL.so.1'
        end
      )
    end

    # Every pixel of the current back buffer, bottom row first (GL's order).
    def grab(width, height)
      read_buffer.call(GL_BACK)
      finish.call # the driver may still be drawing; the read must not race it
      buffer = Fiddle::Pointer.malloc(width * height * 4)
      read_pixels.call(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, buffer)
      Pixels.new(buffer[0, width * height * 4], width, height)
    end

    private

    # An App that draws the caller's block, captures the result once it has
    # been submitted to GL, and stops — one frame, not two.
    def capture_class
      @capture_class ||= Class.new(RGame::Core::App) do
        attr_reader :frame

        def initialize(width, height, block)
          super(width: width, height: height, caption: 'rendered frame')
          @renderer = RGame::Core::Renderer.new(self)
          @block = block
        end

        def draw
          @block.call(@renderer, self)
        end

        def frame_end
          @frame = RenderedFrame.grab(width, height)
          close
        end
      end
    end
  end

  # The captured image, addressed the way the engine addresses the screen:
  # (0, 0) top-left, y downwards.
  class Pixels
    attr_reader :width, :height

    def initialize(bytes, width, height)
      @bytes = bytes
      @width = width
      @height = height
    end

    # [r, g, b, a] at (x, y), each 0..255.
    def at(x, y)
      # GL hands back the bottom row first, so the row index is flipped here —
      # in exactly one place, rather than in every expectation.
      offset = (((@height - 1 - y) * @width) + x) * 4
      @bytes[offset, 4].unpack('C4')
    end

    # Colour comparisons need a little slack: the pixels went through a float
    # pipeline and a software rasteriser, so an exact 255 is not promised.
    def about?(x, y, expected, tolerance: 4)
      at(x, y).zip(expected).all? { |got, want| (got - want).abs <= tolerance }
    end
  end
end
