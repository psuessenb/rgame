# frozen_string_literal: true

module RGame
  module Engine
    # The `:stats` channel of RGame::Engine::Debug, reporting runtime health in the
    # bottom-right corner: frame rate (FPS), the process' cumulative
    # allocated-object count (OBJ), and the objects allocated since the last frame
    # (Δ/f).
    #
    # It holds no flag of its own. `Debug` decides whether the channel is on, and
    # calls #restart when it goes on and #draw while it is.
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
    #
    # **Each row is rounded to an Integer before its digits are taken**, because
    # that loop divides by ten until nothing is left and a Float never gets
    # there: 59.94 walks down through 0.6, 0.06, 0.006 and draws a leading zero
    # at every step, three hundred of them, until the number finally underflows.
    # `App#fps` is a Float, so this is the frame rate's own path rather than a
    # hypothetical one.
    class DebugOverlay
      DIGITS = %w[0 1 2 3 4 5 6 7 8 9].freeze

      FPS_LABEL   = 'FPS'
      OBJ_LABEL   = 'OBJ'
      DELTA_LABEL = 'Δ/f'

      COLOR = [80, 255, 120].freeze
      PAD   = 8
      GAP   = 8

      def initialize
        @prev_allocated = GC.stat(:total_allocated_objects)
        @digit_widths  = Array.new(10)
        @label_widths  = {}
      end

      # Counts Δ/f from now. Called when the channel goes on, so the first frame
      # shown reports one frame's allocations rather than every one since the
      # last time anybody looked.
      def restart = @prev_allocated = GC.stat(:total_allocated_objects)

      # Laid out against the view it is drawn into rather than against the
      # window, so it stays in the corner of whatever region it is given. It
      # takes `fps` rather than reading it, for the same reason nothing here
      # reads a clock: the number is measured by the shell that owns the loop
      # and handed down. See "`draw` renders state".
      # Its own `:debug` band, which is the last one, so this lands over every
      # other thing in the frame however the scene is arranged. Not a node, so
      # it opens its own layer rather than being given one by the traversal.
      def draw(renderer, view, fps)
        allocated = GC.stat(:total_allocated_objects)
        delta = allocated - @prev_allocated
        @prev_allocated = allocated

        line_h  = renderer.text_height
        right_x = view.width - PAD
        top_y   = view.height - PAD - (line_h * 3)

        renderer.layered(:debug) do
          draw_line(renderer, FPS_LABEL, fps, right_x, top_y)
          draw_line(renderer, OBJ_LABEL, allocated, right_x, top_y + line_h)
          draw_line(renderer, DELTA_LABEL, delta, right_x, top_y + (line_h * 2))
        end
      end

      private

      def draw_line(renderer, label, value, right_x, y)
        number_left = draw_uint(renderer, value.round, right_x, y)
        renderer.text(label, number_left - GAP - label_width(renderer, label), y, color: COLOR)
      end

      def draw_uint(renderer, value, right_x, y)
        x = right_x
        more = true
        while more
          digit = value % 10
          value /= 10
          x -= digit_width(renderer, digit)
          renderer.text(DIGITS[digit], x, y, color: COLOR)
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
