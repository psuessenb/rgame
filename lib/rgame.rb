# frozen_string_literal: true

# Entry point for `require "rgame"`.
#
# This deliberately loads only RGame::Util — the half that links no SDL/OpenGL.
# RGame::Core (the window, the main loop) is an explicit opt-in:
#
#   require "rgame"           # Util only, no graphics libraries in the process
#   require "rgame/core"      # adds RGame::Core::App, pulls in SDL + GL
#
# Keeping graphics off the default require is the whole point of splitting the
# two extensions: pure-logic code, and the specs that cover it, must be usable
# with no display and no SDL present.
require_relative 'rgame/version'
require_relative 'rgame/util'
