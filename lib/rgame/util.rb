# frozen_string_literal: true

# RGame::Util — everything that does NOT depend on SDL, OpenGL, or anything
# built on them. Backed by the graphics-free extension in ext/rgame_util/.
# Its counterpart is RGame::Core (see lib/rgame/core.rb).
require_relative 'util/color'
require_relative 'util/controls'
require_relative 'util/tensor'
