# frozen_string_literal: true

module Platform
  # Draws a bordered texture at any size by 9-slicing: the four corners stay fixed,
  # the four edges and the centre are *tiled* (repeated, not stretched) to fill —
  # keeping the pixel art crisp at arbitrary widget sizes. The nine sub-images are
  # cut once at construction (the same Gosu::Image#subimage SpriteSheet uses), so
  # #draw allocates nothing.
  #
  # `scale` is an integer pixel-scale for the chrome itself: source art is small
  # (corners ~7px), so a scale of 2-3 gives legible borders on a 640x480 screen
  # without blurring. Edges/centre tile in scaled steps.
  class NineSlice
    def initialize(image, x:, y:, w:, h:, border:, scale: 1)
      @scale = scale
      @l = border[:left]
      @r = border[:right]
      @t = border[:top]
      @b = border[:bottom]
      cw = w - @l - @r # centre strip width / height, in source pixels
      ch = h - @t - @b

      @tl = image.subimage(x,          y,          @l, @t)
      @tr = image.subimage(x + w - @r, y,          @r, @t)
      @bl = image.subimage(x,          y + h - @b, @l, @b)
      @br = image.subimage(x + w - @r, y + h - @b, @r, @b)
      @top    = image.subimage(x + @l,      y,          cw, @t)
      @bottom = image.subimage(x + @l,      y + h - @b, cw, @b)
      @left   = image.subimage(x,          y + @t,     @l, ch)
      @right  = image.subimage(x + w - @r, y + @t,     @r, ch)
      @centre = image.subimage(x + @l,     y + @t,     cw, ch)
    end

    # Fill the rect (dx, dy, dw, dh). Corners draw at native*scale; edges and centre
    # tile within their bands, each clipped so the last partial tile is cropped cleanly.
    def draw(dx, dy, dw, dh, z:, color: Gosu::Color::WHITE)
      s = @scale
      l = @l * s
      r = @r * s
      t = @t * s
      b = @b * s
      inner_w = dw - l - r
      inner_w = 0 if inner_w.negative?
      inner_h = dh - t - b
      inner_h = 0 if inner_h.negative?

      tile_band(dx + l, dy + t, inner_w, inner_h, @centre, z, color)       # centre
      tile_band(dx + l, dy,          inner_w, t,       @top,    z, color)  # top edge
      tile_band(dx + l, dy + dh - b, inner_w, b,       @bottom, z, color)  # bottom edge
      tile_band(dx,          dy + t, l,       inner_h, @left,   z, color)  # left edge
      tile_band(dx + dw - r, dy + t, r,       inner_h, @right,  z, color)  # right edge

      @tl.draw(dx,          dy,          z, s, s, color)
      @tr.draw(dx + dw - r, dy,          z, s, s, color)
      @bl.draw(dx,          dy + dh - b, z, s, s, color)
      @br.draw(dx + dw - r, dy + dh - b, z, s, s, color)
    end

    private

    # Tile `img` (scaled) across a band, clipped to it so the trailing tile is cropped.
    def tile_band(bx, by, bw, bh, img, z, color)
      return if bw <= 0 || bh <= 0

      s = @scale
      step_x = img.width * s
      step_y = img.height * s
      Gosu.clip_to(bx, by, bw, bh) do
        y = by
        while y < by + bh
          x = bx
          while x < bx + bw
            img.draw(x, y, z, s, s, color)
            x += step_x
          end
          y += step_y
        end
      end
    end
  end
end
