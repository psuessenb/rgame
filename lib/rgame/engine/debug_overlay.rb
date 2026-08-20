# frozen_string_literal: true

module RGame
  module Engine
    # A hard-wired development overlay, toggled by F1 (see RGame::Game), reporting
    # runtime health in the bottom-right corner: frame rate (FPS), the process'
    # cumulative allocated-object count (OBJ), and the objects allocated since the last
    # frame (Δ/f).
    #
    # **Δ/f is the one to watch, and it is a standing guard rather than a
    # diagnostic for one past bug.** A clean per-frame path holds it near zero; a
    # steady nonzero number is a garbage collection being scheduled. The cost is
    # invisible by every other measure — nothing looks wrong, nothing is slower,
    # until a pause lands mid-frame — so without a number on screen it is not
    # noticed at all.
    #
    # Every layer can break it and each has its own way of doing so. Core can
    # allocate in a binding, the engine layer in a component's `draw`, and game
    # code in a scene that builds a string or an array per frame. RuboCop's
    # `Game/NoInterpolationInHotPath` and `Game/NoNeedlessAllocation` catch the
    # shapes they can see in *this* repo; they cannot see a game built on top,
    # and they cannot see an allocation that happens inside a method they think
    # is cheap. This can.
    #
    # Pure: it reads only GC.stat and draws against the renderer interface, so it stays
    # headless-testable. The crux is that it must not allocate while drawing — the values
    # change every frame, so the usual "cache the string, rebuild on change" trick would
    # allocate a String per frame, and the meter would be measuring itself. Instead
    # numbers are drawn digit-by-digit from a fixed set of pre-built single-character
    # strings, which the font caches per glyph.
    class DebugOverlay
      DIGITS = %w[0 1 2 3 4 5 6 7 8 9].freeze

      FPS_LABEL   = 'FPS'
      OBJ_LABEL   = 'OBJ'
      DELTA_LABEL = 'Δ/f'

      COLOR = [80, 255, 120].freeze # frozen so the renderer caches the resolved colour
      Z     = 1_000_000             # above any scene content
      PAD   = 8                     # margin from the screen edge
      GAP   = 8                     # space between a label and its number

      def initialize
        @visible = false
        @prev_allocated = 0
        @digit_widths  = Array.new(10) # measured once, then reused
        @label_widths  = {}            # measured once per label, then reused
      end

      def visible? = @visible

      def toggle
        @visible = !@visible
        # Baseline the counter on reveal so the first Δ/f isn't the whole run's history.
        @prev_allocated = GC.stat(:total_allocated_objects) if @visible
      end

      # Laid out against the view it is drawn into rather than against the
      # window, so it stays in the corner of whatever region it is given. It
      # takes `fps` rather than reading it, for the same reason nothing here
      # reads a clock: the number is measured by the shell that owns the loop
      # and handed down. See CLAUDE.md, "`draw` renders state".
      def draw(renderer, view, fps)
        return unless @visible

        allocated = GC.stat(:total_allocated_objects)
        delta = allocated - @prev_allocated
        @prev_allocated = allocated

        line_h  = renderer.text_height
        right_x = view.x + view.width - PAD
        top_y   = view.y + view.height - PAD - (line_h * 3)

        draw_line(renderer, FPS_LABEL, fps, right_x, top_y)
        draw_line(renderer, OBJ_LABEL, allocated, right_x, top_y + line_h)
        draw_line(renderer, DELTA_LABEL, delta, right_x, top_y + (line_h * 2))
      end

      private

      # A right-aligned "label  number" row ending at right_x.
      def draw_line(renderer, label, value, right_x, y)
        number_left = draw_uint(renderer, value, right_x, y)
        renderer.text(label, number_left - GAP - label_width(renderer, label), y, z: Z, color: COLOR)
      end

      # Draw a non-negative integer right-aligned ending at right_x, digit by digit so no
      # String is built per frame. Returns the x of the leftmost digit.
      def draw_uint(renderer, value, right_x, y)
        x = right_x
        more = true
        while more
          digit = value % 10
          value /= 10
          x -= digit_width(renderer, digit)
          renderer.text(DIGITS[digit], x, y, z: Z, color: COLOR)
          more = value.positive?
        end
        x
      end

      def digit_width(renderer, digit)
        @digit_widths[digit] ||= renderer.text_width(DIGITS[digit])
      end

      def label_width(renderer, label)
        @label_widths[label] ||= renderer.text_width(label)
      end
    end
  end
end
