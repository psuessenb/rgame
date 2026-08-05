# frozen_string_literal: true

module RGame
  module Core
    # A bordered texture drawn at any size, by cutting it into nine pieces and
    # treating each differently.
    #
    #   panel = RGame::Core::NineSlice.new(image, x: 0, y: 0, w: 26, h: 28,
    #                                     border: 7, scale: 3)
    #   panel.draw(renderer, x, y, width, height, z: 0)
    #
    # The four corners keep their size, the four edges stretch along one axis
    # and the centre along both — so one small piece of art fills a button, a
    # dialog or a health bar without the corners smearing.
    #
    # ```
    #   ┌──┬────────┬──┐   corners: fixed
    #   │tl│  top   │tr│   top / bottom: tiled across
    #   ├──┼────────┼──┤   left / right: tiled down
    #   │l │ centre │ r│   centre: tiled both ways
    #   ├──┼────────┼──┤
    #   │bl│ bottom │br│
    #   └──┴────────┴──┘
    # ```
    #
    # **Edges and the centre are *tiled*, not stretched.** Repeating a 7-pixel
    # motif keeps pixel art crisp at any widget size; stretching it would blur
    # exactly the detail the art was drawn for. Each band is clipped to itself,
    # so the last tile in a row is cropped cleanly rather than spilling over the
    # corner next to it.
    #
    # `scale` is an integer pixel scale for the chrome itself. Source art is
    # small — corners are often 7 pixels — so a scale of 2 or 3 gives legible
    # borders on a 640x480 screen without any blurring, because every source
    # pixel becomes a whole square of screen pixels.
    #
    # The nine pieces are cut once at construction, so `#draw` allocates
    # nothing. It is called once per widget per frame.
    class NineSlice
      # `border` is a uniform integer or a hash of `left`/`right`/`top`/`bottom`.
      # (x, y, w, h) is the source rectangle inside `image`, so one sheet can
      # hold many of these — which is what UiAtlas does with it.
      def initialize(image, x:, y:, w:, h:, border:, scale: 1)
        # A zero or negative scale would give every tile a step of zero pixels,
        # and `#draw`'s tiling loops would never advance. Refusing it here costs
        # nothing; a guard inside the loop would cost a branch per tile, per
        # widget, per frame.
        raise ArgumentError, "nine-slice scale must be positive, got #{scale}" unless scale.positive?

        @scale = scale
        border = normalize_border(border)
        @l = border.fetch(:left)
        @r = border.fetch(:right)
        @t = border.fetch(:top)
        @b = border.fetch(:bottom)

        cut_pieces(image, x, y, w, h)
      end

      # Fills the rectangle (dx, dy, dw, dh).
      #
      # `color` tints every piece — a focus highlight, a disabled grey. A
      # rectangle smaller than its own borders draws its corners and nothing
      # else, which is the least misleading thing a widget too small for its own
      # chrome can look like.
      def draw(renderer, dx, dy, dw, dh, z: 0, color: nil)
        s = @scale
        l = @l * s
        r = @r * s
        t = @t * s
        b = @b * s
        # These go negative for a rectangle narrower than its own borders, and
        # are not clamped: #band refuses a non-positive size anyway, so clamping
        # here would be a second guard that cannot change any outcome — and
        # would read as if the case were handled in two places.
        inner_w = dw - l - r
        inner_h = dh - t - b

        band(renderer, @centre, dx + l, dy + t, inner_w, inner_h, z, color)
        band(renderer, @top, dx + l, dy, inner_w, t, z, color)
        band(renderer, @bottom, dx + l, dy + dh - b, inner_w, b, z, color)
        band(renderer, @left, dx, dy + t, l, inner_h, z, color)
        band(renderer, @right, dx + dw - r, dy + t, r, inner_h, z, color)

        # Last, so a tile that reached the edge of its band is covered rather
        # than showing through a corner's transparent pixels.
        piece(renderer, @tl, dx, dy, z, color)
        piece(renderer, @tr, dx + dw - r, dy, z, color)
        piece(renderer, @bl, dx, dy + dh - b, z, color)
        piece(renderer, @br, dx + dw - r, dy + dh - b, z, color)
      end

      private

      # A uniform integer becomes four equal sides. Accepting both shapes here
      # rather than in the callers is what makes `NineSlice.new(image, border: 7,
      # ...)` work on its own — a bare integer would otherwise fail as
      # `7[:left]`, which names nothing that appears in the caller's code.
      def normalize_border(border)
        return border.transform_keys(&:to_sym) unless border.is_a?(Integer)

        { left: border, right: border, top: border, bottom: border }
      end

      def cut_pieces(image, x, y, w, h)
        centre_w = w - @l - @r
        centre_h = h - @t - @b
        if centre_w.negative? || centre_h.negative?
          raise ArgumentError,
                "nine-slice borders (#{@l}, #{@r}, #{@t}, #{@b}) do not fit in a #{w}x#{h} rect"
        end

        @tl = cut(image, x, y, @l, @t)
        @tr = cut(image, x + w - @r, y, @r, @t)
        @bl = cut(image, x, y + h - @b, @l, @b)
        @br = cut(image, x + w - @r, y + h - @b, @r, @b)

        @top = cut(image, x + @l, y, centre_w, @t)
        @bottom = cut(image, x + @l, y + h - @b, centre_w, @b)
        @left = cut(image, x, y + @t, @l, centre_h)
        @right = cut(image, x + w - @r, y + @t, @r, centre_h)
        @centre = cut(image, x + @l, y + @t, centre_w, centre_h)
      end

      # A piece with no pixels is a legitimate part of a legitimate slice — a
      # border with no centre column is a bar that only stretches vertically,
      # and a zero border is one that does not stretch at all on that side. Such
      # a piece is `nil` and simply never drawn; asking `Image#subimage` for it
      # would raise.
      def cut(image, x, y, width, height)
        return nil unless width.positive? && height.positive?

        image.subimage(x, y, width, height)
      end

      def piece(renderer, image, x, y, z, color)
        return unless image

        renderer.image_at(image, x, y, scale_x: @scale, scale_y: @scale, z: z, color: color)
      end

      # Repeats `image` across (bx, by, bw, bh), clipped to it so the trailing
      # tile is cropped instead of overrunning into the next band.
      def band(renderer, image, bx, by, bw, bh, z, color)
        return if image.nil? || bw <= 0 || bh <= 0

        step_x = image.width * @scale
        step_y = image.height * @scale
        renderer.clipped(bx, by, bw, bh) do
          y = by
          while y < by + bh
            x = bx
            while x < bx + bw
              piece(renderer, image, x, y, z, color)
              x += step_x
            end
            y += step_y
          end
        end
      end
    end
  end
end
