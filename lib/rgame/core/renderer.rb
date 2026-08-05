# frozen_string_literal: true

require 'rgame/core_ext'
require_relative 'font'
require_relative '../util/color'

module RGame
  module Core
    # What a game draws with.
    #
    #   class MyGame < RGame::Core::App
    #     def initialize
    #       super(width: 800, height: 600, caption: 'demo')
    #       @renderer = RGame::Core::Renderer.new(self)
    #       @hero = RGame::Core::Image.new(self, 'hero.png')
    #     end
    #
    #     def draw
    #       @renderer.rect(10, 10, 100, 40, color: RGame::Util::Color::WHITE)
    #       @renderer.image(@hero, 400, 300, angle: 45)
    #     end
    #   end
    #
    # Drawing is only legal inside `draw`, and calling one of these outside it
    # raises. That is on purpose: the frame is not open, so the vertices would
    # be silently discarded, and an invisible failure is the worst kind.
    #
    # Nothing is drawn immediately. Calls accumulate and are z-sorted when the
    # frame closes, so `z:` decides what ends up on top — not call order. Equal
    # z keeps call order, which is what stops same-layer sprites flickering
    # between frames.
    #
    # The C half of this class (ext/rgame_core/ruby/renderer_ext.c) has the `draw_*`
    # and `push_*` primitives; everything here is the comfortable surface over
    # them.
    #
    # ## Colours
    #
    # Every drawing method takes `color:`, accepting whatever `Color.coerce`
    # does: `nil` (white — an untinted draw), `[r, g, b]`, `[r, g, b, a]`, or a
    # `RGame::Util::Color`. Passing a `Color` is the allocation-free path and is
    # what per-frame code should do; an array allocates one colour per call.
    class Renderer
      Color = RGame::Util::Color

      # Shapes default above sprites, so a debug box or a health bar drawn
      # without a `z:` lands on top of the scene rather than under it. The
      # values match the layer this replaces.
      SHAPE_Z = 50
      IMAGE_Z = 0

      # Enough segments that a circle reads as round at the sizes a 2D game
      # draws one, and few enough that a screenful of them is still one batch.
      CIRCLE_SEGMENTS = 64

      # Text defaults above sprites but below shapes, and the size matches what
      # the layer this replaces used, so ported UI lays out unchanged.
      TEXT_Z = 10
      FONT_SIZE = 18

      # Translucent red, for #debug_box.
      DEBUG_BOX_COLOR = Color.new(255, 40, 40, 120)

      # `assets:` is where a draw id that is not registered gets resolved from,
      # and defaults to the app's own manager — so the common case wires itself
      # and `renderer.sprite('hero.json', …)` works with nothing set up.
      #
      # A Ruby `self.new` because the C `initialize` has fixed arity and no
      # business knowing what an asset manager is; the same shape `Font`'s
      # `path:` uses.
      def self.new(app, assets: nil)
        renderer = super(app)
        renderer.assets = assets.nil? ? app.assets : assets
        renderer
      end

      attr_accessor :assets

      # --- draw-by-id ---------------------------------------------------------
      #
      # Game logic names assets, it does not hold them: the engine layer may
      # hold `RGame::Util` values but no `RGame::Core` handle at all, so a
      # Symbol or a path is the only thing a node *can* carry. Resolving it is
      # this side of the boundary's job.
      #
      # An id is normally a **root-relative path**, resolved through the asset
      # manager and then remembered, so a per-frame draw neither re-resolves nor
      # allocates a lookup key:
      #
      #   renderer.sprite('example 09/player.json', row, col, x, y)
      #
      # `register_*` pre-binds an id to a chosen object, for the two things a
      # path cannot name: an id that is not a file (nine-slice ids are *atlas
      # element* names) and an object the game assembled itself.

      def register_image(id, image) = registry(:image)[id] = image
      def register_sheet(id, sheet) = registry(:sheet)[id] = sheet
      def register_tilemap(id, tilemap) = registry(:tilemap)[id] = tilemap
      def register_nine_slice(id, nine_slice) = registry(:nine_slice)[id] = nine_slice

      # Registers every element of a UiAtlas under its own name, since those
      # names are what a widget asks for.
      def register_ui_atlas(atlas)
        atlas.nine_slices.each { |id, nine_slice| register_nine_slice(id, nine_slice) }
        self
      end

      # One frame of a registered or resolvable sprite sheet, top-left at (x, y).
      def sprite(id, row, col, x, y, flip_x: false, z: IMAGE_Z)
        lookup(:sheet, id).draw(self, row, col, x, y, flip_x: flip_x, z: z)
      end

      # A nine-slice filling (x, y, width, height), tinted by `tint` if given.
      # Registration only: a nine-slice id names an element of an atlas, not a
      # file, so there is nothing for the asset manager to resolve it to.
      def nine_slice(id, x, y, width, height, z: IMAGE_Z, tint: nil)
        lookup(:nine_slice, id).draw(self, x, y, width, height, z: z, color: tint)
      end

      # A tile map's below-the-actor band (ground and same-level detail).
      #
      # `elapsed` is the seconds its animated tiles have been running for, and
      # is an argument rather than a clock read on purpose — see CLAUDE.md,
      # "`draw` renders state; time enters through `update`". A scene
      # accumulates it in `update`, which is what makes pausing work.
      def tilemap(id, camera_x, camera_y, viewport_width, viewport_height, elapsed: 0.0)
        lookup(:tilemap, id)
          .draw(self, camera_x, camera_y, viewport_width, viewport_height, elapsed: elapsed)
      end

      # Its above-the-actor band (canopies, roofs), at a `z` the scene picks so
      # it lands over the actors.
      def tilemap_overlay(id, camera_x, camera_y, viewport_width, viewport_height,
                          z:, elapsed: 0.0)
        lookup(:tilemap, id).draw_overlay(self, camera_x, camera_y, viewport_width,
                                          viewport_height, z: z, elapsed: elapsed)
      end

      # A filled axis-aligned rectangle.
      def rect(x, y, width, height, z: SHAPE_Z, color: nil)
        draw_rect(x, y, width, height, z, packed(color))
      end

      # Four arbitrary points, in loop order: listing them in Z order gives an
      # hourglass rather than a shape.
      def quad(x1, y1, x2, y2, x3, y3, x4, y4, z: SHAPE_Z, color: nil)
        draw_quad(x1, y1, x2, y2, x3, y3, x4, y4, z, packed(color))
      end

      def triangle(x1, y1, x2, y2, x3, y3, z: SHAPE_Z, color: nil)
        draw_triangle(x1, y1, x2, y2, x3, y3, z, packed(color))
      end

      # A line of real thickness — drawn as a quad, because GL's own line width
      # is a suggestion drivers may ignore above one pixel.
      def line(x1, y1, x2, y2, thickness: 1.0, z: SHAPE_Z, color: nil)
        draw_line(x1, y1, x2, y2, thickness, z, packed(color))
      end

      # A filled circle, as a fan of triangles around its centre.
      def circle(cx, cy, radius, z: SHAPE_Z, color: nil, segments: CIRCLE_SEGMENTS)
        draw_circle(cx, cy, radius, segments, z, packed(color))
      end

      # An image centred on (cx, cy), rotated `angle` degrees clockwise about
      # that centre and uniformly scaled. Unrotated and unscaled is a fast path
      # that skips the transform stack entirely.
      #
      # Takes an `Image` or an id for one — see #resolve_image.
      def image(image, cx, cy, angle: 0, scale: 1, z: IMAGE_Z, color: nil)
        draw_image_rot(resolve_image(image), cx, cy, angle, scale, z, packed(color))
      end

      # An image with its top-left at (x, y), scaled independently per axis —
      # a tile, a nine-slice corner, a sprite-sheet frame.
      #
      # A **negative scale mirrors the image inside the same rectangle**; it
      # does not move it. So a frame drawn at (x, y) covers the same pixels
      # whichever way it faces, and `scale_x: -1` means "facing the other way"
      # rather than "one width to the left":
      #
      #   renderer.image_at(frame, x, y, scale_x: facing_left ? -1 : 1)
      #
      # A zero scale draws nothing.
      def image_at(image, x, y, scale_x: 1, scale_y: 1, z: IMAGE_Z, color: nil)
        draw_image_scaled(resolve_image(image), x, y, scale_x, scale_y, z, packed(color))
      end

      # An image with its top-left at (x, y), at its natural size — a
      # full-screen backdrop by default. `image_at` with both scales at 1, kept
      # because "put this at the origin" is worth a name of its own.
      def background(image, x = 0, y = 0, z: IMAGE_Z, color: nil)
        draw_image(resolve_image(image), x, y, z, packed(color))
      end

      # Everything drawn in the block is rotated `angle` degrees about
      # (pivot_x, pivot_y), so a node can spin all of its parts coherently
      # around one point.
      #
      # A zero angle skips the push entirely — unrotated drawing pays nothing,
      # which matters because most drawing is unrotated.
      def rotated(angle, pivot_x, pivot_y)
        return yield if angle.zero?

        push_rotate(angle, pivot_x, pivot_y)
        begin
          yield
        ensure
          # An ensure, not a plain pop: a scene that raises mid-draw would
          # otherwise leave the stack deeper than it found it, and every
          # later frame would draw askew for a reason nothing points at.
          pop
        end
      end

      # Everything drawn in the block is shifted by (dx, dy) screen pixels —
      # the camera's view transform. Because it is a draw-time transform rather
      # than something baked into positions, the same world can be drawn again
      # under a different offset and clip, which is what split-screen is.
      def translated(dx, dy)
        return yield if dx.zero? && dy.zero?

        push_translate(dx, dy)
        begin
          yield
        ensure
          pop
        end
      end

      def scaled(sx, sy = sx)
        return yield if sx == 1 && sy == 1

        push_scale(sx, sy)
        begin
          yield
        ensure
          pop
        end
      end

      # Everything drawn in the block is confined to the given rectangle.
      #
      # A clip only ever narrows: nesting one inside another intersects them, so
      # a child cannot draw outside the region its parent allowed. Give each
      # player a clipped block and you have split-screen.
      def clipped(x, y, width, height)
        push_clip(x, y, width, height)
        begin
          yield
        ensure
          pop
        end
      end

      # The font this renderer draws with when a call does not name one.
      #
      # Built on first use rather than in the constructor: creating a font needs
      # a GL context, and a renderer is often built before there is one. Set
      # your own with #font= to change what every unqualified #text call uses.
      def font
        @font ||= Font.new(app, FONT_SIZE)
      end

      attr_writer :font

      # One line of text, with its top-left corner at (x, y) — the same corner
      # every other drawing method takes, rather than the baseline typography
      # would use.
      #
      # Newlines are not special. A caller wanting two lines draws two, stepping
      # by #text_height.
      def text(string, x, y, z: TEXT_Z, color: nil, font: nil)
        draw_text(font || self.font, string, x, y, z, packed(color))
      end

      # What #text would occupy, for centring and layout. Unlike the drawing
      # methods this works outside `draw`, because measuring touches no GL.
      def text_width(string, font: nil) = (font || self.font).text_width(string)

      # The line height: what to step y by for a second line.
      def text_height(font: nil) = (font || self.font).height

      # Bakes everything the block draws into a RGame::Core::Recording, which
      # can then be replayed for the cost of one call per texture however many
      # draws went into it. Nothing is drawn *now* — the block's output goes
      # into the recording instead of into this frame.
      #
      #   ground = renderer.record { tiles.each { |t| renderer.image(t.img, t.x, t.y) } }
      #   ground.draw(-camera.x, -camera.y)
      #
      # Recording happens inside `draw` like everything else, and does not
      # nest. A clip pushed inside the block raises: clipping cannot be baked,
      # so clip the replay instead. See RGame::Core::Recording.
      def record
        begin_record
        completed = false
        begin
          yield
          completed = true
        ensure
          # A block that raised leaves a half-built recording open, and the
          # next frame would keep drawing into it. Unwinding here means the
          # exception is the only thing the caller has to deal with.
          cancel_record unless completed
        end
        end_record
      end

      # A translucent overlay for visualising a collision box, so a scene can
      # ask for one without knowing what colour "debug" is.
      def debug_box(x, y, width, height, z: SHAPE_Z)
        rect(x, y, width, height, z: z, color: DEBUG_BOX_COLOR)
      end

      private

      # Colours cross into C as a packed integer. `Color.coerce` is the single
      # place nil/array/Color are turned into one, so no drawing method has its
      # own idea of what a colour is.
      def packed(color) = Color.coerce(color).packed

      # An `Image` is already what it is; anything else is an id for one.
      #
      # The two callers this serves cannot be reconciled any other way. Core's
      # own drawing classes — SpriteSheet, NineSlice — hold real images and pass
      # them; the engine layer is forbidden from holding one and can only pass
      # an id. Dispatching on the type keeps both spellings of `#image` and
      # `#background` working without two parallel method names for the same
      # picture.
      def resolve_image(image) = image.is_a?(Image) ? image : lookup(:image, image)

      def registry(type) = (@registries ||= {})[type] ||= {}

      # Prefer an explicit registration, otherwise ask the asset manager, then
      # remember the answer — so a per-frame draw neither re-resolves nor
      # allocates a lookup key.
      def lookup(type, id)
        # `nil` is never an id, and reporting it as one ("no image registered
        # for nil") describes a typo when the actual bug is an asset that
        # resolved to nothing. The two want different fixes.
        raise TypeError, "no implicit conversion of nil into #{type}" if id.nil?

        table = registry(type)
        table.fetch(id) { table[id] = resolve_asset(type, id) }
      end

      # Only a String is offered to the asset manager, because only a String can
      # be a path. A Symbol id is a name a game chose, so a missing one is the
      # KeyError below — naming the id — rather than whatever the manager makes
      # of being handed a Symbol where it wanted a filename.
      #
      # `respond_to?` for the same reason one step along: the manager grows an
      # accessor per asset type, and asking for one it does not have yet should
      # be this error rather than a NoMethodError from inside it.
      def resolve_asset(type, id)
        resolved = @assets.public_send(type, id) if id.is_a?(String) && @assets.respond_to?(type)
        resolved || raise(KeyError, "no #{type} registered for #{id.inspect} " \
                                    'and no AssetManager to resolve it')
      end
    end
  end
end
