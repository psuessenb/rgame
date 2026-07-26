# frozen_string_literal: true

module RGame
  # A fixed-size 3-D grid backed by a single flat array, addressed as [x, y, z] —
  # Matrix's sibling for data that is naturally three-dimensional, e.g. a tile map's
  # stacked layers ([col, row, layer]). Layout is x-fastest then y then z, so one
  # z-slice ([*, *, z]) is a contiguous run. Pure; no bounds checking on the hot path.
  class Tensor
    attr_reader :width, :height, :depth

    def initialize(width, height, depth, initial: nil)
      @width = width
      @height = height
      @depth = depth
      @plane = width * height
      @data = Array.new(@plane * depth, initial)
    end

    def [](x, y, z)
      @data[(z * @plane) + (y * @width) + x]
    end

    def []=(x, y, z, value)
      @data[(z * @plane) + (y * @width) + x] = value
    end
  end
end