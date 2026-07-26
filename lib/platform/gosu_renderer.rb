# frozen_string_literal: true

module Platform
  # Renderer implementation backed by Gosu. Scenes draw against this interface
  # (sprite/text/…); tests substitute a recording fake with the same methods.
  class GosuRenderer
    FONT_SIZE = 18
    DEBUG_BOX_COLOR = Gosu::Color.new(120, 255, 40, 40)
    # The unit-circle texture is built once at this resolution and drawn scaled/tinted
    # for every #circle call, so a primitive circle is one draw call (no per-frame
    # triangle fan). 64 px reads crisp scaled down and acceptably smooth scaled up a bit.
    CIRCLE_TEXTURE_DIAMETER = 64
    CIRCLE_SEGMENTS = 64

    def initialize(assets: nil)
      @assets       = assets
      @sheets       = {}
      @tilemaps     = {}
      @images       = {}
      @nine_slices  = {}
      @color_cache  = {}
      @font         = Gosu::Font.new(FONT_SIZE)
    end

    def register_sheet(id, sheet)
      @sheets[id] = sheet
    end

    def register_tilemap(id, tilemap_renderer)
      @tilemaps[id] = tilemap_renderer
    end

    # A single standalone image: a rotating Asteroids entity (drawn centred via
    # #image) or a full-screen backdrop (drawn at the origin via #background).
    # Store an already-loaded image under an id. Loading + caching is the
    # AssetManager's job, so this (like register_sheet/register_ui_atlas) just
    # records the object for draw-by-id.
    def register_image(id, image)
      @images[id] = image
    end

    def register_nine_slice(id, nine_slice)
      @nine_slices[id] = nine_slice
    end

    # Register every element of a Platform::UiAtlas in one call.
    def register_ui_atlas(atlas)
      atlas.nine_slices.each { |id, nine_slice| @nine_slices[id] = nine_slice }
    end

    def sprite(id, row, col, x, y, flip_x: false, z: 0)
      sheet_for(id).draw(row, col, x, y, flip_x: flip_x, z: z)
    end

    # The tilemap's below-the-actor band (ground + same-level detail).
    def tilemap(id, camera_x, camera_y, viewport_width, viewport_height)
      tilemap_for(id).draw(camera_x, camera_y, viewport_width, viewport_height)
    end

    # The tilemap's above-the-actor band (canopies, roofs), drawn at `z` so the scene
    # can place it over its actors.
    def tilemap_overlay(id, camera_x, camera_y, viewport_width, viewport_height, z:)
      tilemap_for(id).draw_overlay(camera_x, camera_y, viewport_width, viewport_height, z: z)
    end

    # Run the given draws rotated `angle` degrees about the pivot (pivot_x, pivot_y),
    # so a node can spin all of its primitives coherently around one point — its
    # absolute origin. Callers convert the node's radian angle to degrees, e.g.
    #
    #   renderer.rotated(abs_angle * 180.0 / Math::PI, abs_x, abs_y) do
    #     renderer.nine_slice(:panel, abs_x, abs_y, width, height, z: abs_z)
    #   end
    #
    # Zero-angle fast path skips the Gosu call (and any block allocation) entirely,
    # so unrotated drawing pays nothing.
    def rotated(angle, pivot_x, pivot_y)
      return yield if angle.zero?

      # `yield` over an explicit `&block`: capturing the block as a Proc would
      # allocate on every rotated draw, which this hot path must avoid.
      Gosu.rotate(angle, pivot_x, pivot_y) { yield } # rubocop:disable Style/ExplicitBlockArgument
    end

    # Run the given draws shifted by (dx, dy) screen pixels — the camera's view
    # transform. A scene maps world space to the screen by drawing its world subtree
    # inside translated(-camera.x, -camera.y); because it's a draw-time transform (not
    # baked into any node's position) the same world can later be drawn through several
    # cameras (split-screen) by repeating the block under different offsets/clips.
    # Zero-offset fast path skips the Gosu call (and block allocation), like #rotated.
    def translated(dx, dy)
      return yield if dx.zero? && dy.zero?

      Gosu.translate(dx, dy) { yield } # rubocop:disable Style/ExplicitBlockArgument
    end

    # Draw a registered image centred at (cx, cy), rotated `angle` degrees
    # (clockwise, 0 = upright) and uniformly scaled.
    def image(id, cx, cy, angle: 0, scale: 1, z: 0)
      image_for(id).draw_rot(cx, cy, z, angle, 0.5, 0.5, scale, scale)
    end

    # Draw a registered image at the origin as a full-screen backdrop.
    def background(id, z: 0)
      image_for(id).draw(0, 0, z)
    end

    # Draw a registered 9-slice texture filling (x, y) .. (x+width, y+height), tinted
    # by `tint` if given (e.g. a focus highlight). Widgets draw their chrome through this.
    def nine_slice(id, x, y, width, height, z: 0, tint: nil)
      @nine_slices.fetch(id).draw(x, y, width, height, z: z, color: resolve_color(tint))
    end

    # Gosu::Font caches per *glyph*, so drawing arbitrary/changing strings (scores,
    # timers) reuses cached glyph textures — object count stays bounded by the glyph
    # set, not by the number of distinct strings. (A whole-string image cache would be
    # ≈zero per-frame cost for static labels but grows one GPU image per distinct
    # string forever — unbounded for dynamic text — so we don't.)
    def text(string, x, y, z: 10, color: nil)
      @font.draw_text(string, x, y, z, 1, 1, resolve_color(color))
    end

    # Font metrics, so pure widgets can centre/measure labels without touching Gosu.
    def text_width(string) = @font.text_width(string)
    def text_height = @font.height

    # Filled rectangle (z above sprites by default).
    def rect(x, y, width, height, z: 50, color: nil)
      Gosu.draw_rect(x, y, width, height, resolve_color(color), z)
    end

    # Filled circle of `radius` centred at (cx, cy). Backed by one cached unit-circle
    # texture drawn scaled + tinted, so each call is a single draw and allocates nothing.
    def circle(cx, cy, radius, z: 50, color: nil)
      image = circle_image
      scale = (radius * 2.0) / image.width
      image.draw_rot(cx, cy, z, 0, 0.5, 0.5, scale, scale, resolve_color(color))
    end

    # A straight line of the given `thickness` from (x1, y1) to (x2, y2), drawn as a
    # quad (a perpendicular-offset rectangle) so thickness is honoured — unlike
    # Gosu.draw_line, which is always one pixel. Allocation-free.
    def line(x1, y1, x2, y2, thickness: 1.0, z: 50, color: nil)
      c = resolve_color(color)
      dx = x2 - x1
      dy = y2 - y1
      length = Math.sqrt((dx * dx) + (dy * dy))
      return if length.zero?

      # Half-thickness perpendicular offset (ox, oy), folded straight into the corner
      # add/subtracts below. We deliberately do NOT form the negated component (e.g.
      # `-dy`) on its own: for an axis-aligned segment that intermediate is a *computed*
      # negative zero, which CRuby heap-allocates (it isn't a flonum) — so a screenful of
      # horizontal/vertical lines would leak Floats every frame. Building each corner as
      # `x ∓ ox` / `y ± oy` keeps every intermediate a flonum.
      scale = (thickness / 2.0) / length
      ox = dy * scale
      oy = dx * scale
      Gosu.draw_quad(x1 - ox, y1 + oy, c, x2 - ox, y2 + oy, c,
                     x1 + ox, y1 - oy, c, x2 + ox, y2 - oy, c, z)
    end

    # Translucent overlay for visualising a collision box. Scenes call this so
    # they don't need to know about Gosu colours.
    def debug_box(x, y, width, height)
      rect(x, y, width, height, DEBUG_BOX_COLOR)
    end

    private

    # Lazily render a white filled unit circle once (needs a live GL context, so it
    # can't be built in #initialize) and cache it. A triangle fan around the centre.
    def circle_image
      @circle_image ||= Gosu.render(CIRCLE_TEXTURE_DIAMETER, CIRCLE_TEXTURE_DIAMETER) do
        r = CIRCLE_TEXTURE_DIAMETER / 2.0
        white = Gosu::Color::WHITE
        step = (2 * Math::PI) / CIRCLE_SEGMENTS
        CIRCLE_SEGMENTS.times do |i|
          a0 = i * step
          a1 = (i + 1) * step
          Gosu.draw_triangle(r, r, white,
                             r + (Math.cos(a0) * r), r + (Math.sin(a0) * r), white,
                             r + (Math.cos(a1) * r), r + (Math.sin(a1) * r), white)
        end
      end
    end

    # Resolve a draw id to its asset, preferring an explicit registration and otherwise
    # asking the AssetManager (by symbol or path), then caching the object so repeated
    # draws don't re-resolve (and don't allocate a lookup key per frame). A clear error
    # if neither a registration nor an AssetManager can supply it.
    def sheet_for(id) = (@sheets[id] ||= resolve_asset(:sheet, id))
    def image_for(id) = (@images[id] ||= resolve_asset(:image, id))
    def tilemap_for(id) = (@tilemaps[id] ||= resolve_asset(:tilemap, id))

    def resolve_asset(type, id)
      @assets&.public_send(type, id) ||
        raise(KeyError, "no #{type} registered for #{id.inspect} and no AssetManager to resolve it")
    end

    # Accept an engine-side colour without the engine knowing Gosu: nil → white,
    # an [r, g, b] / [r, g, b, a] array → a Gosu colour, or an existing Gosu::Color
    # passed straight through.
    def resolve_color(color)
      return Gosu::Color::WHITE if color.nil?
      return color unless color.is_a?(Array)

      cached_color(color)
    end

    def cached_color(color)
      @color_cache[color] ||= Gosu::Color.rgba(color[0], color[1], color[2], color[3] || 255)
    end
  end
end
