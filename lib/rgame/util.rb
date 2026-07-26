# frozen_string_literal: true

# RGame::Util — everything that does NOT depend on SDL, OpenGL, or anything
# built on them. Backed by the graphics-free extension in ext/rgame_util/.
# Its counterpart is RGame::Platform (see lib/rgame/platform.rb).
require_relative 'util/tensor'
