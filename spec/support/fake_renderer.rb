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
  attr_accessor :assets

  def initialize(assets: nil)
    @calls = []
    @transforms = []
    @recording = nil
    @assets = assets
    @registries = {}
  end

  # --- draw-by-id ---------------------------------------------------------
  #
  # The same two-step the real renderer does: prefer a registration, otherwise
  # ask an asset manager, and only a String is offered to one because only a
  # String can be a path. A spec that wants to assert *which* asset a scene
  # asked for reads the recorded call; a spec that wants the lookup to fail
  # registers nothing.

  def register_image(id, image) = registry(:image)[id] = image
  def register_sheet(id, sheet) = registry(:sheet)[id] = sheet
  def register_tilemap(id, tilemap) = registry(:tilemap)[id] = tilemap
  def register_nine_slice(id, nine_slice) = registry(:nine_slice)[id] = nine_slice

  def register_ui_atlas(atlas)
    atlas.nine_slices.each { |id, nine_slice| register_nine_slice(id, nine_slice) }
    self
  end

  def sprite(id, row, col, x, y, flip_x: false, z: 0)
    lookup(:sheet, id).draw(self, row, col, x, y, flip_x: flip_x, z: z)
  end

  def nine_slice(id, x, y, width, height, z: 0, tint: nil)
    lookup(:nine_slice, id).draw(self, number(x), number(y), number(width), number(height),
                                 z: number(z), color: color_arg(tint))
  end

  # The rectangle is a cull rect in world coordinates, not an offset: the map
  # draws where it lives and the caller's transform places it.
  def tilemap(id, cull_x, cull_y, cull_width, cull_height, elapsed: 0.0)
    lookup(:tilemap, id)
      .draw(self, cull_x, cull_y, cull_width, cull_height, elapsed: number(elapsed))
  end

  def tilemap_overlay(id, cull_x, cull_y, cull_width, cull_height, z:, elapsed: 0.0)
    lookup(:tilemap, id).draw_overlay(self, cull_x, cull_y, cull_width,
                                      cull_height, z: z, elapsed: number(elapsed))
  end

  # --- refusing what the real renderer refuses ------------------------------
  #
  # The real renderer's arguments cross into C through NUM2DBL, StringValue and
  # an Image unwrap, every one of which raises TypeError on the wrong kind of
  # object. A fake that accepted them would let `renderer.text(nil, x, y)` — a
  # label that was never set, an i18n lookup that missed — pass a headless spec
  # and then raise in the game. See CLAUDE.md, "A fake must refuse what the real
  # thing refuses".
  #
  # These validate without converting: the recorded call keeps exactly what the
  # caller passed, so assertions read as written.

  def number(value)
    raise TypeError, "no implicit conversion of #{value.class} into Float" unless value.is_a?(Numeric)

    value
  end

  def string(value)
    raise TypeError, "no implicit conversion of #{value.class} into String" unless value.is_a?(String)

    value
  end

  # A StubImage stands in for a live Image and is used as-is; anything else is
  # an id for one, exactly as the real renderer treats a `Core::Image` versus a
  # Symbol or path. A stand-in *type* is what makes that dispatch possible at
  # all — before there was one, a Symbol was ambiguous between "this is the
  # image" and "this names the image".
  def image_arg(value)
    value.is_a?(StubImage) ? value : lookup(:image, value)
  end

  # Runs the *same* coercion the real renderer runs, so the two cannot disagree
  # about what a colour is, then records what the caller actually passed.
  def color_arg(value)
    RGame::Util::Color.coerce(value)
    value
  end

  # --- shapes -------------------------------------------------------------

  def rect(x, y, width, height, z: 50, color: nil)
    remember(:rect, [number(x), number(y), number(width), number(height)],
             z: number(z), color: color_arg(color))
  end

  def quad(x1, y1, x2, y2, x3, y3, x4, y4, z: 50, color: nil)
    remember(:quad, [number(x1), number(y1), number(x2), number(y2),
                     number(x3), number(y3), number(x4), number(y4)],
             z: number(z), color: color_arg(color))
  end

  def triangle(x1, y1, x2, y2, x3, y3, z: 50, color: nil)
    remember(:triangle, [number(x1), number(y1), number(x2), number(y2), number(x3), number(y3)],
             z: number(z), color: color_arg(color))
  end

  def line(x1, y1, x2, y2, thickness: 1.0, z: 50, color: nil)
    remember(:line, [number(x1), number(y1), number(x2), number(y2)],
             thickness: number(thickness), z: number(z), color: color_arg(color))
  end

  def circle(cx, cy, radius, z: 50, color: nil, segments: 64)
    remember(:circle, [number(cx), number(cy), number(radius)],
             z: number(z), color: color_arg(color), segments: number(segments))
  end

  def debug_box(x, y, width, height, z: 50)
    remember(:debug_box, [number(x), number(y), number(width), number(height)], z: number(z))
  end

  # --- images -------------------------------------------------------------

  def image(image, cx, cy, angle: 0, scale: 1, z: 0, color: nil)
    remember(:image, [image_arg(image), number(cx), number(cy)],
             angle: number(angle), scale: number(scale), z: number(z), color: color_arg(color))
  end

  def image_at(image, x, y, scale_x: 1, scale_y: 1, z: 0, color: nil)
    remember(:image_at, [image_arg(image), number(x), number(y)],
             scale_x: number(scale_x), scale_y: number(scale_y), z: number(z),
             color: color_arg(color))
  end

  def background(image, x = 0, y = 0, z: 0, color: nil)
    remember(:background, [image_arg(image), number(x), number(y)],
             z: number(z), color: color_arg(color))
  end

  # --- text ---------------------------------------------------------------

  def text(string, x, y, z: 10, color: nil, font: nil)
    remember(:text, [string(string), number(x), number(y)],
             z: number(z), color: color_arg(color), font: font)
  end

  # Stand-in metrics. They are not the real font's — a fake has no glyphs — but
  # they are *ordered* the way real ones are: zero for an empty string and
  # growing with its length. A scene that centres a label works out a different
  # number here than in the game, and that is inherent; what it must not do is
  # divide by zero or lay text out backwards.
  # `font:` is accepted and ignored — the interface has it, and a fake has no
  # font to distinguish. A spec that cares which font a scene asked for reads it
  # off the recorded #text call instead.
  CHARACTER_WIDTH = 8.0
  LINE_HEIGHT = 18

  def text_width(string, font: nil)
    _ = font
    string(string).length * CHARACTER_WIDTH
  end

  def text_height(font: nil)
    _ = font
    LINE_HEIGHT
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

  def rotated(angle, pivot_x, pivot_y, &)
    within(:rotated, [number(angle), number(pivot_x), number(pivot_y)], &)
  end

  def translated(dx, dy, &) = within(:translated, [number(dx), number(dy)], &)
  def scaled(sx, sy = sx, &) = within(:scaled, [number(sx), number(sy)], &)

  def clipped(x, y, width, height, &)
    # The real renderer cannot bake a clip — clipping happens when pixels are
    # rasterised — so neither may this, or a scene would pass its specs and
    # then raise in the game.
    raise 'a clip cannot be recorded — wrap the replay in #clipped instead' if @recording

    [x, y, width, height].each { |value| number(value) }

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
  def registry(type) = @registries[type] ||= {}

  def lookup(type, id)
    raise TypeError, "no implicit conversion of nil into #{type}" if id.nil?

    table = registry(type)
    table.fetch(id) { table[id] = resolve_asset(type, id) }
  end

  def resolve_asset(type, id)
    resolved = @assets.public_send(type, id) if id.is_a?(String) && @assets.respond_to?(type)
    resolved || raise(KeyError, "no #{type} registered for #{id.inspect} " \
                                'and no AssetManager to resolve it')
  end

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
