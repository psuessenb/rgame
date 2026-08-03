# frozen_string_literal: true

# A renderer that draws nothing and remembers everything.
#
# This is what a headless spec hands a scene in place of the real thing. The
# engine layer only ever calls a renderer by method name, so a node cannot tell
# the difference — and a spec gets to assert on *what was drawn* rather than on
# pixels, which is both more precise and possible with no window at all:
#
#   renderer = FakeRenderer.new
#   node.draw(renderer)
#
#   expect(renderer.calls_to(:rect).map(&:args)).to eq([[10, 20, 30, 40]])
#   expect(renderer.drawn?(:circle)).to be(true)
#
# Transform blocks are recorded *and* run, so anything drawn inside one is
# recorded too — and each recorded call carries the transform depth it happened
# at, which is how a spec checks that a node's parts were drawn inside its
# rotation rather than beside it.
#
# It is checked against the same shared contract as the real renderer (see
# fake_renderer_spec.rb). If the two drift, `rake spec` would stay green while
# the game stopped running, which is exactly the failure the headless/Core split
# cannot catch on its own.
class FakeRenderer
  # One recorded call. `depth` is how many transform blocks were open at the
  # time; `transforms` is the stack of those blocks, outermost first.
  Call = Struct.new(:name, :args, :options, :transforms) do
    def depth = transforms.size
  end

  attr_reader :calls

  def initialize
    @calls = []
    @transforms = []
  end

  # --- shapes -------------------------------------------------------------

  def rect(x, y, width, height, z: 50, color: nil)
    record(:rect, [x, y, width, height], z: z, color: color)
  end

  def quad(x1, y1, x2, y2, x3, y3, x4, y4, z: 50, color: nil)
    record(:quad, [x1, y1, x2, y2, x3, y3, x4, y4], z: z, color: color)
  end

  def triangle(x1, y1, x2, y2, x3, y3, z: 50, color: nil)
    record(:triangle, [x1, y1, x2, y2, x3, y3], z: z, color: color)
  end

  def line(x1, y1, x2, y2, thickness: 1.0, z: 50, color: nil)
    record(:line, [x1, y1, x2, y2], thickness: thickness, z: z, color: color)
  end

  def circle(cx, cy, radius, z: 50, color: nil, segments: 64)
    record(:circle, [cx, cy, radius], z: z, color: color, segments: segments)
  end

  def debug_box(x, y, width, height, z: 50)
    record(:debug_box, [x, y, width, height], z: z)
  end

  # --- images -------------------------------------------------------------

  def image(image, cx, cy, angle: 0, scale: 1, z: 0, color: nil)
    record(:image, [image, cx, cy], angle: angle, scale: scale, z: z, color: color)
  end

  def background(image, x = 0, y = 0, z: 0, color: nil)
    record(:background, [image, x, y], z: z, color: color)
  end

  # --- transform blocks ---------------------------------------------------

  def rotated(angle, pivot_x, pivot_y, &) = within(:rotated, [angle, pivot_x, pivot_y], &)
  def translated(dx, dy, &) = within(:translated, [dx, dy], &)
  def scaled(sx, sy = sx, &) = within(:scaled, [sx, sy], &)
  def clipped(x, y, width, height, &) = within(:clipped, [x, y, width, height], &)

  # --- reading it back ----------------------------------------------------

  def calls_to(name) = @calls.select { |call| call.name == name }
  def drawn?(name) = @calls.any? { |call| call.name == name }

  def clear
    @calls.clear
    self
  end

  private

  def record(name, args, **options)
    @calls << Call.new(name, args, options, @transforms.dup)
    self
  end

  def within(name, args)
    record(name, args)
    @transforms.push(Call.new(name, args, {}, []))
    begin
      yield
    ensure
      # Matching the real renderer's `ensure`: a block that raises must still
      # leave the stack where it found it, or every later call is recorded at
      # the wrong depth and the spec lies about what happened.
      @transforms.pop
    end
  end
end
