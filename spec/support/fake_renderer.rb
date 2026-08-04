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
    @recording = nil
  end

  # --- shapes -------------------------------------------------------------

  def rect(x, y, width, height, z: 50, color: nil)
    remember(:rect, [x, y, width, height], z: z, color: color)
  end

  def quad(x1, y1, x2, y2, x3, y3, x4, y4, z: 50, color: nil)
    remember(:quad, [x1, y1, x2, y2, x3, y3, x4, y4], z: z, color: color)
  end

  def triangle(x1, y1, x2, y2, x3, y3, z: 50, color: nil)
    remember(:triangle, [x1, y1, x2, y2, x3, y3], z: z, color: color)
  end

  def line(x1, y1, x2, y2, thickness: 1.0, z: 50, color: nil)
    remember(:line, [x1, y1, x2, y2], thickness: thickness, z: z, color: color)
  end

  def circle(cx, cy, radius, z: 50, color: nil, segments: 64)
    remember(:circle, [cx, cy, radius], z: z, color: color, segments: segments)
  end

  def debug_box(x, y, width, height, z: 50)
    remember(:debug_box, [x, y, width, height], z: z)
  end

  # --- images -------------------------------------------------------------

  def image(image, cx, cy, angle: 0, scale: 1, z: 0, color: nil)
    remember(:image, [image, cx, cy], angle: angle, scale: scale, z: z, color: color)
  end

  def background(image, x = 0, y = 0, z: 0, color: nil)
    remember(:background, [image, x, y], z: z, color: color)
  end

  # --- recording ----------------------------------------------------------

  # Bakes the block into a FakeRecording. The calls made inside are recorded on
  # the recording rather than here, which is what lets a spec check both what a
  # scene baked *and* where it later drew it.
  def record
    raise 'already recording (recordings do not nest)' if @recording

    @recording = FakeRecording.new(self)
    begin
      yield
    rescue StandardError
      @recording = nil
      raise
    end
    @recording.tap { @recording = nil }
  end

  # --- transform blocks ---------------------------------------------------

  def rotated(angle, pivot_x, pivot_y, &) = within(:rotated, [angle, pivot_x, pivot_y], &)
  def translated(dx, dy, &) = within(:translated, [dx, dy], &)
  def scaled(sx, sy = sx, &) = within(:scaled, [sx, sy], &)

  def clipped(x, y, width, height, &)
    # The real renderer cannot bake a clip — clipping happens when pixels are
    # rasterised — so neither may this, or a scene would pass its specs and
    # then raise in the game.
    raise 'a clip cannot be recorded — wrap the replay in #clipped instead' if @recording

    within(:clipped, [x, y, width, height], &)
  end

  # --- reading it back ----------------------------------------------------

  def calls_to(name) = @calls.select { |call| call.name == name }
  def drawn?(name) = @calls.any? { |call| call.name == name }

  def clear
    @calls.clear
    self
  end

  # `remember` is private, but FakeRecording reaches it through `send` when a
  # replay happens — the two are one mechanism split across two files.
  private

  def remember(name, args, **options)
    call = Call.new(name, args, options, @transforms.dup)
    # While baking, calls belong to the recording rather than to this frame —
    # the real renderer diverts them the same way, by swapping the canvas they
    # land on.
    (@recording ? @recording.calls : @calls) << call
    self
  end

  def within(name, args)
    remember(name, args)
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
