# frozen_string_literal: true

# Entry point for `require "rgame"`: everything that runs without a window.
#
#   require 'rgame'         # RGame::Util + RGame::Engine — no graphics libraries
#   require 'rgame/core'    # adds the window, the GPU and the sound device
#   require 'rgame/game'    # all of it, wired together
#
# Each line is a strict superset of the one above, and the split is the point.
# **This one loads no SDL and no OpenGL** — `RGame::Util` is a graphics-free
# extension and `RGame::Engine` is pure Ruby — so game logic and the specs that
# cover it run with no display present. `spec/rgame/no_graphics_spec.rb` holds
# that up rather than leaving it to good intentions.
#
# Nothing is forced through this file. `rgame/util`, `rgame/engine` and
# `rgame/core` are separately requirable, which is how the Core spec suite loads
# exactly one layer and gets a `NameError` if it reaches for another.
require_relative 'rgame/version'
require_relative 'rgame/util'
require_relative 'rgame/engine'
