# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

require_relative 'crate'
require_relative 'flag'
require_relative 'hero'
require_relative 'hud'
require_relative 'raft'
require_relative 'walker'
require_relative 'course'

WIDTH  = 640
HEIGHT = 480
DEFAULT_SEED = 0xC0

ASSETS = File.expand_path('../../examples/assets', __dir__)
Controls = RGame::Util::Controls

game = RGame::Game.new(
  root: Course.new,
  caption: 'Top-down platformer',
  width: WIDTH,
  height: HEIGHT,
  media_root: ASSETS,
  seed: DEFAULT_SEED,
  players: 2,
  input_map: RGame::Engine::InputMap.default.merge(
    jump: { buttons: [Controls::KEY_SPACE, Controls::PAD_A] }
  )
)

game.start
