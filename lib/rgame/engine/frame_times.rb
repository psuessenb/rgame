# frozen_string_literal: true

module RGame
  module Engine
    # Which frame of a looping sequence shows after some seconds. A sheet's
    # animation and a map's animated tile both ask it. Each keeps its own clock
    # and its own frames, and hands in only the seconds.
    #
    #   FrameTimes.even(6, 1.0 / 8).index_at(0.4)       # => 3
    #   FrameTimes.new([0.1, 0.35, 0.4]).index_at(0.2)  # => 1
    #
    # **It takes the second each frame ends at, not how long each lasts.** A
    # Tiled tile's frames last whole milliseconds, and `TileMap.from_tiled`
    # adds them up as Integers before it turns them into seconds. Adding the
    # seconds up would move an end: 0.1 + 0.25 + 0.05 is 0.39999999999999997.
    #
    # **An even sequence divides**, for the same reason. At 6 fps a frame lasts
    # 1/6 s, which a Float cannot hold exactly, and searching ends made from it
    # could move a frame change by a tick.
    #
    # @api private
    class FrameTimes
      # `count` frames of `seconds` each: a sheet's animation at its fps.
      def self.even(count, seconds) = Even.new(count, seconds)

      # `ends` holds the second each frame ends at, into the loop, so the last
      # one is the loop's length.
      def initialize(ends)
        @ends = ends.dup.freeze
        @length = @ends.last
        @last = @ends.size - 1
      end

      # The frame showing after `elapsed` seconds, counted from 0. It loops, and
      # at a frame's exact end the next one shows. Allocates nothing.
      def index_at(elapsed)
        into = elapsed % @length
        @ends.index { into < it } || @last
      end

      # Frames of one length, found by dividing. It answers `index_at` as a
      # FrameTimes does, and keeps no ends.
      class Even
        def initialize(count, seconds)
          @count = count
          @seconds = seconds
        end

        def index_at(elapsed) = (elapsed / @seconds).floor % @count
      end
      private_constant :Even
    end
  end
end
