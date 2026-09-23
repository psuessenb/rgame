# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

require_relative 'chest'
require_relative 'coin'
require_relative 'debug_toggle'
require_relative 'hero'
require_relative 'room'
require_relative 'shell'

WIDTH  = 640
HEIGHT = 480

ASSETS = File.expand_path('../../examples/assets', __dir__)
Controls = RGame::Util::Controls

game = RGame::Game.new(
  root: Shell.new,
  caption: 'Adventure',
  width: WIDTH,
  height: HEIGHT,
  media_root: ASSETS,
  players: 2,
  input_map: RGame::Engine::InputMap.default.merge(
    debug: { buttons: [Controls::KEY_F4, Controls::PAD_BACK] },
    interact: { buttons: [Controls::KEY_E, Controls::PAD_X], tap: 0.3 },
    search: { buttons: [Controls::KEY_E, Controls::PAD_X], hold: 0.6 }
  )
)

game.start
