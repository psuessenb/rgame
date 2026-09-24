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
  Z = RGame::Util::Z

  # One recorded call. `depth` is how many transform blocks were open at the
  # time; `transforms` is the stack of those blocks, outermost first.
  #
  # `layer` is the z base in effect — the slot #layered handed out — and `key`
  # is what the real renderer would actually sort on. That is what makes draw
  # *order* assertable from a headless spec: `calls.sort_by(&:key)` is the order
  # the frame comes out in, so "the canopy is above the actor" stops being
  # something only a human looking at a window can check.
  Call = Struct.new(:name, :args, :options, :transforms, :layer) do
    def depth = transforms.size
    def key = layer + (options[:z] || 0)
  end

  attr_reader :calls
  attr_accessor :assets

  def initialize(assets: nil)
    @calls = []
    @transforms = []
    @recording = nil
    @assets = assets
    @registries = {}
    reset_layers
  end

  # --- layers -------------------------------------------------------------

  # The z base every subsequent `z:` is measured from. 0 outside any #layered.
  attr_reader :layer

  # A fresh slot in `band`, for the block's drawing to be an offset from.
  # Mirrors the real renderer exactly, down to using the same RGame::Util::Z
  # arithmetic rather than reimplementing it — the numbers a spec asserts on are
  # therefore the numbers the game sorts on.
  def layered(band = Z::DEFAULT)
    index = Z.index(band)
    previous = @layer
    @layer = Z.slot_base(index, @slots[index])
    @slots[index] += 1
    begin
      yield
    ensure
      @layer = previous
    end
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
    atlas.images.each { |id, image| register_image(id, image) }
    self
  end

  def sprite(id, row, col, x, y, flip_x: false, z: 0)
    lookup(:sheet, id).draw(self, row, col, x, y, flip_x: flip_x, z: z)
  end

  def nine_slice(id, x, y, width, height, z: 0, tint: nil)
    lookup(:nine_slice, id).draw(self, number(x), number(y), number(width), number(height),
                                 z: z_arg(z), color: color_arg(tint))
  end

  # The rectangle is a cull rect in world coordinates, not an offset: the map
  # draws where it lives and the caller's transform places it.
  def tilemap(id, layer, cull_x, cull_y, cull_width, cull_height, elapsed: 0.0)
    lookup(:tilemap, id).draw_layer(self, number(layer), cull_x, cull_y, cull_width,
                                    cull_height, elapsed: number(elapsed))
  end

  # --- refusing what the real renderer refuses ------------------------------
  #
  # The real renderer's arguments cross into C through NUM2DBL, StringValue and
  # an Image unwrap, every one of which raises TypeError on the wrong kind of
  # object. A fake that accepted them would let `renderer.text(nil, x, y)` — a
  # label that was never set, an i18n lookup that missed — pass a headless spec
  # and then raise in the game.
  # See "A fake must refuse what the real thing refuses".
  #
  # These validate without converting: the recorded call keeps exactly what the
  # caller passed, so assertions read as written. A label is the one exception;
  # see #string.

  def number(value)
    raise TypeError, "no implicit conversion of #{value.class} into Float" unless value.is_a?(Numeric)

    value
  end

  # A label converts the way StringValue converts it: through `to_str`, which
  # is how a node draws its Text as it is. Unlike the other checks this records
  # the converted String rather than the object, because a Text changes after it
  # is drawn and a recorded call has to say what that frame showed.
  def string(value)
    value = value.to_str if !value.is_a?(String) && value.respond_to?(:to_str)
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

  # Likewise for z: the real renderer refuses anything outside one node's slot,
  # because a `z:` orders a node's own drawing and the band comes from the tree.
  # A stale global z (`z: 100_000`) has to raise here too, or a scene still
  # passing one would sail through the headless suite.
  def z_arg(value) = Z.offset(value)

  # --- shapes -------------------------------------------------------------

  def rect(x, y, width, height, z: 0, color: nil)
    remember(:rect, [number(x), number(y), number(width), number(height)],
             z: z_arg(z), color: color_arg(color))
  end

  def quad(x1, y1, x2, y2, x3, y3, x4, y4, z: 0, color: nil)
    remember(:quad, [number(x1), number(y1), number(x2), number(y2),
                     number(x3), number(y3), number(x4), number(y4)],
             z: z_arg(z), color: color_arg(color))
  end

  def triangle(x1, y1, x2, y2, x3, y3, z: 0, color: nil)
    remember(:triangle, [number(x1), number(y1), number(x2), number(y2), number(x3), number(y3)],
             z: z_arg(z), color: color_arg(color))
  end

  def line(x1, y1, x2, y2, thickness: 1.0, z: 0, color: nil)
    remember(:line, [number(x1), number(y1), number(x2), number(y2)],
             thickness: number(thickness), z: z_arg(z), color: color_arg(color))
  end

  def circle(cx, cy, radius, z: 0, color: nil, segments: 64)
    remember(:circle, [number(cx), number(cy), number(radius)],
             z: z_arg(z), color: color_arg(color), segments: number(segments))
  end

  def debug_box(x, y, width, height, z: 0)
    remember(:debug_box, [number(x), number(y), number(width), number(height)], z: z_arg(z))
  end

  def debug_circle(cx, cy, radius, z: 0)
    remember(:debug_circle, [number(cx), number(cy), number(radius)], z: z_arg(z))
  end

  # --- images -------------------------------------------------------------

  def image(image, cx, cy, angle: 0, scale: 1, z: 0, color: nil)
    remember(:image, [image_arg(image), number(cx), number(cy)],
             angle: number(angle), scale: number(scale), z: z_arg(z), color: color_arg(color))
  end

  def image_at(image, x, y, scale_x: 1, scale_y: 1, z: 0, color: nil)
    remember(:image_at, [image_arg(image), number(x), number(y)],
             scale_x: number(scale_x), scale_y: number(scale_y), z: z_arg(z),
             color: color_arg(color))
  end

  def background(image, x = 0, y = 0, z: 0, color: nil)
    remember(:background, [image_arg(image), number(x), number(y)],
             z: z_arg(z), color: color_arg(color))
  end

  # --- text ---------------------------------------------------------------

  # Records the part of the string a real renderer shows, so a spec reads a
  # revealed line as the prefix on screen, whichever way it was drawn.
  def text(string, x, y, z: 0, color: nil, font: nil, bytes: nil)
    remember(:text, [shown(string(string), bytes), number(x), number(y)],
             z: z_arg(z), color: color_arg(color), font: font)
  end

  # What `bytes:` leaves of `string`: its first `bytes` bytes, shortened to the
  # last whole character, as the real renderer's C cuts it.
  def shown(string, bytes)
    return string if bytes.nil?

    limit = Integer(number(bytes))
    raise ArgumentError, "bytes: must not be negative, got #{limit}" if limit.negative?
    return string if limit >= string.bytesize

    limit -= 1 while limit.positive? && (string.getbyte(limit) & 0xC0) == 0x80
    string.byteslice(0, limit)
  end

  # Real metrics: the shipped typeface at the renderer's size, measured by the
  # same C the live renderer's font runs. So a scene that centres a label
  # computes here the number it computes in the game, and a spec can assert the
  # position. `font:` is a Typeface to measure with instead; a spec that cares
  # which font a scene drew with reads it off the recorded #text call.
  def typeface = RGame::Util::Typeface.default

  def text_width(string, font: nil) = (font || typeface).text_width(string(string))

  def text_height(font: nil) = (font || typeface).height

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

  # Ends this frame's record. The slot counters go back to zero with it: the
  # real renderer's are reset by the frame beginning, and a fake that kept
  # counting would give the same node a different layer every frame.
  def clear
    @calls.clear
    reset_layers
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

  def reset_layers
    @layer = 0
    @slots = Array.new(Z::BANDS.size, 0)
  end

  def remember(name, args, **options)
    call = Call.new(name, args, options, @transforms.dup, @layer)
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
