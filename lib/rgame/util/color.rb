# frozen_string_literal: true

require 'rgame/util_ext'

module RGame
  module Util
    class Color
      RED = new(255, 0, 0)
      GREEN = new(0, 255, 0)
      BLUE = new(0, 0, 255)
      YELLOW = new(255, 255, 0)
      CYAN = new(0, 255, 255)
      MAGENTA = new(255, 0, 255)
      ORANGE = new(255, 165, 0)
      PURPLE = new(128, 0, 128)
      BROWN = new(139, 69, 19)
      PINK = new(255, 192, 203)
      GRAY = new(128, 128, 128)
      LIGHT_GRAY = new(192, 192, 192)
      DARK_GRAY = new(64, 64, 64)
    end
  end
end
