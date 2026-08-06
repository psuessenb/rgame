# frozen_string_literal: true

module RGame
  module Engine
    # A fixed-size 2-D grid backed by a single flat (row-major) array, addressed as
    # [x, y]. The flat backing keeps the whole grid in one contiguous allocation —
    # cheaper than an array-of-arrays and a straightforward shape to later move into a
    # C-level buffer. Pure; no bounds checking on the hot path (callers stay in range).
    #
    # This stays Ruby, unlike the engine's old `Tensor`, which was deleted in
    # favour of the C `RGame::Util::Tensor`. The reason is only that there is no
    # C `Util::Matrix` to swap to — `Util` holds `Tensor`, `Controls` and
    # `Color`. If one is ever written, this is the caller to point at it.
    class Matrix
      attr_reader :width, :height

      def initialize(width, height, initial: nil)
        @width = width
        @height = height
        @data = Array.new(width * height, initial)
      end

      def [](x, y)
        @data[(y * @width) + x]
      end

      def []=(x, y, value)
        @data[(y * @width) + x] = value
      end
    end
  end
end
