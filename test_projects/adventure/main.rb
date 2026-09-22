# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

require_relative 'hero'
require_relative 'room'
require_relative 'shell'

WIDTH  = 640
HEIGHT = 480

ASSETS = File.expand_path('../../examples/assets', __dir__)

game = RGame::Game.new(
  root: Shell.new,
  caption: 'Adventure',
  width: WIDTH,
  height: HEIGHT,
  media_root: ASSETS,
  players: 2
)

game.start
