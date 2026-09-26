# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

# The game's own module. `Engine` and `Util` inside it are short for
# `RGame::Engine` and `RGame::Util`. Every file below opens the module again, so
# it is defined here, before the first of them loads.
module Asteroids
  Engine = RGame::Engine
  Util = RGame::Util
  Controls = Util::Controls
end

require_relative 'high_scores'
require_relative 'start_scene'
require_relative 'play_scene'
require_relative 'game_over_scene'

module Asteroids
  WIDTH  = 640
  HEIGHT = 480
  MEDIA  = File.join(__dir__, '../../media')

  # Root: owns scene navigation (SceneStack) and program-lifetime state (HighScores,
  # a global/root-scoped system). A scene asks for the next one through #go, and the
  # stack lands the switch after the tick, so a scene never tears itself down
  # mid-traversal.
  class Root < Engine::Node2D
    def initialize
      super
      @stack = add_component(Engine::Scene::SceneStack.new)
      @stack.define(:start) { StartScene.new }
      @stack.define(:play) { PlayScene.new(width: WIDTH, height: HEIGHT) }
      @stack.define(:game_over) { |score:| GameOverScene.new(score: score) }
      add_component(HighScores.new)
    end

    def _enter_tree = go(:start)

    def go(name, **) = @stack.replace(name, **)
  end

  def self.start
    game = RGame::Game.new(
      root: Root.new,
      caption: 'Asteroids',
      width: WIDTH,
      height: HEIGHT,
      media_root: MEDIA,
      input_map: Engine::InputMap.new(
        turn: { axis: [Controls::KEY_LEFT, Controls::KEY_RIGHT], stick: Controls::AXIS_LEFT_X },
        thrust: { axis: [Controls::KEY_DOWN, Controls::KEY_UP], stick: Controls::AXIS_TRIGGER_RIGHT },
        fire: { buttons: [Controls::KEY_SPACE, Controls::PAD_A] }
      )
    )

    game.renderer.register_image(:space,  game.assets.image('space.png'))
    game.renderer.register_image(:ship,   game.assets.image('example 09/player.png'))
    game.renderer.register_image(:rock,   game.assets.image('example 09/rock_000.png'))
    game.renderer.register_image(:bullet, game.assets.image('example 09/bullet.png'))

    game.audio.register_sound(:shoot, game.assets.sound('example 09/shoot.ogg'))
    game.audio.register_sound(:boom,  game.assets.sound('example 09/boom.ogg'))
    game.audio.register_sound(:hurt,  game.assets.sound('example 09/hurt.ogg'))
    game.audio.register_sound(:blip,  game.assets.sound('example 09/blip.ogg'))
    game.audio.register_music(:heartbeat, game.assets.song('example 09/heartbeat.ogg'))

    game.start
  end
end

Asteroids.start
