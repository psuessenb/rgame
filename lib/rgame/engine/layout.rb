# frozen_string_literal: true

module RGame
  module Engine
    # Where each viewport goes on screen: pure rectangle arithmetic, and nothing
    # else.
    #
    #   Layout.rects(2, 640, 480)   # => [[0, 0, 640, 240], [0, 240, 640, 240]]
    #
    # No state, no anchors, no lifetime — so it is specced on its own with no
    # tree and no window, which is the point of separating it from Viewports.
    # That system holds *which* mode is current and *who* is playing; this only
    # answers "given a count and a window, where do they go".
    #
    # ## Rects tile exactly
    #
    # Edges are computed as `(i * total) / count` rather than by multiplying a
    # rounded size, so three rows of a 481-pixel window are 161, 160 and 160 and
    # the last one still ends exactly at 481. Dividing first leaves a seam at the
    # bottom of the screen that nothing draws into — a one-pixel line that looks
    # like a rendering bug and is really a rounding one.
    module Layout
      # A window's worth of rows, columns or cells for `count` viewports.
      #
      # Two players get rows rather than columns because halving the height of a
      # landscape window leaves each view landscape, while halving the width
      # leaves two tall slots that fit a 2D scene badly. Three and four share a
      # 2x2 grid, with the fourth cell left empty for three.
      # Forwards its block with `&block` rather than re-yielding through
      # `{ |*args| yield(*args) }`, which builds an Array per yield. Passing a
      # block straight on allocates nothing — measured, not assumed; see the
      # allocation example in layout_spec.rb.
      def self.each_rect(count, width, height, &)
        return if count <= 0
        return yield(0, 0, 0, width, height) if count == 1
        return each_row(count, width, height, &) if count == 2

        each_cell(count, 2, 2, width, height, &)
      end

      # The same, as an Array of `[x, y, width, height]`. For specs and setup;
      # the per-frame path uses #each_rect, which allocates nothing.
      def self.rects(count, width, height)
        result = []
        each_rect(count, width, height) { |_i, x, y, w, h| result << [x, y, w, h] }
        result
      end

      # `count` full-width rows, stacked.
      def self.each_row(count, width, height)
        count.times do |i|
          top = edge(i, count, height)
          yield(i, 0, top, width, edge(i + 1, count, height) - top)
        end
      end

      # `count` full-height columns, side by side.
      def self.each_column(count, width, height)
        count.times do |i|
          left = edge(i, count, width)
          yield(i, left, 0, edge(i + 1, count, width) - left, height)
        end
      end

      # The first `count` cells of a `cols` x `rows` grid, filled left to right,
      # top to bottom.
      def self.each_cell(count, cols, rows, width, height)
        count.times do |i|
          col = i % cols
          row = i / cols
          left = edge(col, cols, width)
          top = edge(row, rows, height)
          yield(i, left, top, edge(col + 1, cols, width) - left, edge(row + 1, rows, height) - top)
        end
      end

      # The i-th boundary of `count` even divisions of `total`. Multiplying
      # before dividing is what makes the divisions tile with no seam.
      def self.edge(index, count, total) = (index * total) / count
    end
  end
end
