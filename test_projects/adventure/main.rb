# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

require_relative 'bag'
require_relative 'caption'
require_relative 'chest'
require_relative 'coin'
require_relative 'crate'
require_relative 'debug_toggle'
require_relative 'door'
require_relative 'garden'
require_relative 'hero'
require_relative 'item'
require_relative 'lever'
require_relative 'shell'
require_relative 'sign'
require_relative 'sparkles'
require_relative 'storm'
require_relative 'town'
require_relative 'world'

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
    bag: { buttons: [Controls::KEY_I, Controls::PAD_START] },
    debug: { buttons: [Controls::KEY_F4, Controls::PAD_BACK] },
    interact: { buttons: [Controls::KEY_E, Controls::PAD_X], tap: 0.3 },
    search: { buttons: [Controls::KEY_E, Controls::PAD_X], hold: 0.6 },
    skip: { buttons: [Controls::KEY_TAB, Controls::PAD_Y], hold: 0.6 }
  )
)

game.start
