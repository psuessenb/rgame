# frozen_string_literal: true

# RGame::Core — everything that depends on SDL, OpenGL, or anything built on
# them. Requiring this file loads those libraries into the process, which is why
# it is NOT required from lib/rgame.rb; ask for it explicitly:
#
#   require "rgame/core"
#
# Its counterpart is RGame::Util (see lib/rgame/util.rb), which stays free of
# graphics dependencies.
require_relative 'core/app'
