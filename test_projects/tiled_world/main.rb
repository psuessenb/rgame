# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

Controls = RGame::Util::Controls
require_relative 'cutscene'
require_relative 'inventory'
require_relative 'beach_scene'

WIDTH  = 640
HEIGHT = 480
MEDIA  = File.join(__dir__, '../../media')

# Minimal root: a SceneStack with the single beach scene pushed once it's live.
class Root < RGame::Engine::Node2D
  def initialize
    super
    @stack = add_component(RGame::Engine::Scene::SceneStack.new)
  end

  def on_add = @stack.push(BeachScene.new)
end

game = RGame::Game.new(
  root: Root.new,
  caption: 'Tiled World',
  width: WIDTH,
  height: HEIGHT,
  media_root: MEDIA,
  input_map: RGame::Engine::InputMap.default.merge(
    cutscene: { buttons: [Controls::KEY_TAB, Controls::PAD_START] }
  ),
  players: 2
)

game.renderer.register_ui_atlas(game.assets.ui_atlas('ui/ui_atlas.json'))

game.start
