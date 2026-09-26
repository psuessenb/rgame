# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

# The game's own module. `Engine`, `Util`, `UI` and `Components` inside it stand
# for rgame's namespaces of the same names. Every file below opens the module
# again, so it is defined here, before the first of them loads.
module TopDownPlatformer
  Engine = RGame::Engine
  Util = RGame::Util
  UI = Engine::UI
  Components = Engine::Components
  Controls = Util::Controls
end

require_relative 'crate'
require_relative 'flag'
require_relative 'hero'
require_relative 'hud'
require_relative 'raft'
require_relative 'walker'
require_relative 'course'

module TopDownPlatformer
  WIDTH  = 640
  HEIGHT = 480
  DEFAULT_SEED = 0xC0

  ASSETS = File.expand_path('../../examples/assets', __dir__)

  def self.start
    game = RGame::Game.new(
      root: Course.new,
      caption: 'Top-down platformer',
      width: WIDTH,
      height: HEIGHT,
      media_root: ASSETS,
      seed: DEFAULT_SEED,
      players: 2,
      input_map: Engine::InputMap.default.merge(
        jump: { buttons: [Controls::KEY_SPACE, Controls::PAD_A] }
      )
    )

    game.start
  end
end

TopDownPlatformer.start
