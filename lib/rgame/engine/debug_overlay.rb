# frozen_string_literal: true

module RGame
  module Engine
    # The `:stats` channel of RGame::Engine::Debug: four rows in the bottom-right
    # corner of the view.
    #
    # | Row | Shows |
    # |---|---|
    # | FPS | the frame rate the loop measured |
    # | OBJ | every object the process has allocated so far |
    # | OBJ/s | the objects allocated over the last whole second |
    # | GC ms | the longest the collector ran in one tick of that second |
    #
    # It holds no flag of its own. `Debug` calls #restart when the channel goes
    # on, and #update once a tick and #draw once a frame while it is on.
    #
    # **OBJ/s and GC ms answer different questions, and a game needs both.**
    # OBJ/s drives how often the collector runs. It counts a whole second rather
    # than one frame, because work done on an event allocates in bursts: five
    # objects every third frame reads 0, 0, 5 frame by frame, and 100 a second.
    # GC ms is what a collection cost when it came. At one tick a frame, it is
    # the worst frame's collection: the share of a hitch the collector caused.
    #
    # Every layer can raise OBJ/s, each in its own way. Core can allocate in a
    # binding, the engine layer in a component, and a game in a scene that
    # builds a string per frame. RuboCop's `Game/NoInterpolationInHotPath` and
    # `Game/NoNeedlessAllocation` catch the shapes they can see in *this* repo.
    # They cannot see a game built on top, or an allocation inside a method
    # they think is cheap. This can.
    #
    # **It samples in #update, never in #draw.** Time enters through `update`,
    # so the second the rows cover is one second of `dt`, and a spec ends one by
    # passing 1.0. Drawing shows numbers already taken. OBJ/s and GC ms read 0
    # until the first whole second after #restart.
    #
    # **It reads the collector's clock only on a tick the collector worked
    # in**: when `GC.count` moved, or the whole milliseconds of
    # `GC.stat(:time)` did. `GC.total_time` counts nanoseconds, and on 64-bit
    # Windows an Integer of 2**30 or more is a Bignum, so after a second of
    # collecting every read of it allocates there. Lazy sweeping that adds
    # less than a millisecond after a collection's tick is counted on the next
    # tick the clock is read. The same limit reaches OBJ once the process has
    # allocated 2**30 objects, and nothing here avoids it: `GC.stat` answers
    # with the Bignum.
    #
    # Drawing must not allocate, or the overlay would count itself. A cached
    # String would still be rebuilt each time a number changed, and every
    # rebuild allocates. So each digit is drawn on its own, from a fixed set of
    # single-character strings the font caches per glyph.
    #
    # **Each row is an Integer before its digits are taken**, because that loop
    # divides by ten until nothing is left, and a Float never gets there: 59.94
    # walks down through 0.6, 0.06 and 0.006, drawing a leading zero at every
    # step until it underflows. `App#fps` is a Float, so the frame rate is
    # rounded, and GC ms is kept as a whole number of tenths.
    class DebugOverlay
      DIGITS = %w[0 1 2 3 4 5 6 7 8 9].freeze
      POINT = '.'

      FPS_LABEL  = 'FPS'
      OBJ_LABEL  = 'OBJ'
      RATE_LABEL = 'OBJ/s'
      GC_LABEL   = 'GC ms'
      ROWS = 4

      WINDOW_SECONDS = 1.0
      NS_PER_TENTH_MS = 100_000

      COLOR = Util::Color.new(80, 255, 120)
      PAD   = 8
      GAP   = 8

      def initialize
        @digit_widths = Array.new(10)
        @string_widths = {}
        restart
      end

      # Starts a fresh second, and zeroes OBJ/s and GC ms until it is over.
      # Called when the channel goes on, so the first second shown counts from
      # then rather than from the last time anybody looked.
      def restart
        @allocated = GC.stat(:total_allocated_objects)
        @window_allocated = @allocated
        @gc_count = GC.count
        @gc_ms = GC.stat(:time)
        @gc_ns = GC.total_time
        @worst_gc_ns = 0
        @elapsed = 0.0
        @per_second = 0
        @gc_tenths = 0
      end

      # Takes one tick's sample: the allocation count, and how long the
      # collector ran since the tick before. Once a second of `dt` has passed,
      # it publishes that second's OBJ/s and GC ms and starts the next.
      def update(dt)
        @allocated = GC.stat(:total_allocated_objects)
        time_collector if collector_worked?
        @elapsed += dt
        close_window if @elapsed >= WINDOW_SECONDS
      end

      # Laid out against the view it is drawn into rather than against the
      # window, so it stays in the corner of whatever region it is given. It
      # takes `fps` rather than reading it, for the same reason nothing here
      # reads a clock: the number is measured by the shell that owns the loop
      # and handed down. See "`draw` renders state".
      # Its own `:debug` band, which is the last one, so this lands over every
      # other thing in the frame however the scene is arranged. Not a node, so
      # it opens its own layer rather than being given one by the traversal.
      def draw(renderer, view, fps)
        line_h  = renderer.text_height
        right_x = view.width - PAD
        y       = view.height - PAD - (line_h * ROWS)

        renderer.layered(:debug) do
          label(renderer, FPS_LABEL, draw_uint(renderer, fps.round, right_x, y), y)
          y += line_h
          label(renderer, OBJ_LABEL, draw_uint(renderer, @allocated, right_x, y), y)
          y += line_h
          label(renderer, RATE_LABEL, draw_uint(renderer, @per_second, right_x, y), y)
          y += line_h
          label(renderer, GC_LABEL, draw_tenths(renderer, @gc_tenths, right_x, y), y)
        end
      end

      private

      def collector_worked?
        count = GC.count
        ms = GC.stat(:time)
        return false if count == @gc_count && ms == @gc_ms

        @gc_count = count
        @gc_ms = ms
        true
      end

      def time_collector
        gc_ns = GC.total_time
        spent = gc_ns - @gc_ns
        @worst_gc_ns = spent if spent > @worst_gc_ns
        @gc_ns = gc_ns
      end

      def close_window
        @per_second = (@allocated - @window_allocated).fdiv(@elapsed).round
        @gc_tenths = (@worst_gc_ns + (NS_PER_TENTH_MS / 2)) / NS_PER_TENTH_MS
        @window_allocated = @allocated
        @worst_gc_ns = 0
        @elapsed = 0.0
      end

      def label(renderer, text, number_left, y)
        renderer.text(text, number_left - GAP - string_width(renderer, text), y, color: COLOR)
      end

      def draw_tenths(renderer, tenths, right_x, y)
        x = draw_uint(renderer, tenths % 10, right_x, y) - string_width(renderer, POINT)
        renderer.text(POINT, x, y, color: COLOR)
        draw_uint(renderer, tenths / 10, x, y)
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

      def string_width(renderer, string)
        @string_widths[string] ||= renderer.text_width(string)
      end
    end
  end
end
