# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

# The game's own module. `Engine`, `Util`, `UI` and `Components` inside it stand
# for rgame's namespaces of the same names. Every file below opens the module
# again, so it is defined here, before the first of them loads.
module TiledWorld
  Engine = RGame::Engine
  Util = RGame::Util
  UI = Engine::UI
  Components = Engine::Components
  Controls = Util::Controls
end

require_relative 'cutscene'
require_relative 'inventory'
require_relative 'beach_scene'

module TiledWorld
  WIDTH  = 640
  HEIGHT = 480
  MEDIA  = File.join(__dir__, '../../media')
  DEFAULT_SEED = 0xBEAC4

  # Minimal root: a SceneStack with the single beach scene pushed once it's live.
  class Root < Engine::Node2D
    def initialize
      super
      @stack = add_component(Engine::Scene::SceneStack.new)
    end

    def _enter_tree = @stack.push(BeachScene.new)
  end

  def self.start
    game = RGame::Game.new(
      root: Root.new,
      caption: 'Tiled World',
      width: WIDTH,
      height: HEIGHT,
      media_root: MEDIA,
      seed: DEFAULT_SEED,
      input_map: Engine::InputMap.default.merge(
        cutscene: { buttons: [Controls::KEY_TAB, Controls::PAD_START] }
      ),
      players: 2
    )

    game.renderer.register_ui_atlas(game.assets.ui_atlas('ui/ui_atlas.json'))

    game.start
  end
end

TiledWorld.start
