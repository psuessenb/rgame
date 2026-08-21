# frozen_string_literal: true

# Example 14 — Asteroids.
#
# A full small game on the Node2D/Component architecture, exercising it end to end:
#   - three scenes (start → play → game-over) navigated through a SceneStack;
#   - a scene-scoped CollisionWorld system + a root-scoped HighScores system
#     (the two service scopes — see docs/api/systems.md);
#   - reusable components: Velocity, ScreenWrap, DespawnOffscreen, CircleCollider,
#     Sprite, ThrustController, ActionTrigger;
#   - pooled bullets and rocks (RGame::Engine::Pool) with deferred removal (queue_free);
#   - audio via the global AudioBus + AudioDirector.

# lib/ on the load path, so `require 'rgame/game'` resolves the same way it
# would from an installed gem — which is also how the compiled extensions are
# found.
$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

Controls = RGame::Util::Controls

require_relative 'high_scores'
require_relative 'start_scene'
require_relative 'play_scene'
require_relative 'game_over_scene'

WIDTH  = 640
HEIGHT = 480
MEDIA  = File.join(__dir__, '../../media')

# Root: owns scene navigation (SceneStack) and program-lifetime state (HighScores,
# a global/root-scoped system). Scene switches are deferred to #on_update so a scene
# never tears itself down mid-traversal — #go only records the request, and Root's
# on_update (which runs after the active scene's whole update has unwound) applies it.
class Root < RGame::Engine::Node2D
  def initialize
    super
    @stack = add_component(RGame::Engine::Scene::SceneStack.new)
    add_component(HighScores.new)
    @pending = nil
  end

  def on_add = go(:start)

  def go(name, **args)
    @pending = [name, args]
  end

  def on_update(_dt)
    return unless @pending

    name, args = @pending
    @pending = nil
    @stack.replace(build_scene(name, **args))
  end

  private

  def build_scene(name, score: 0)
    case name
    when :start     then StartScene.new(width: WIDTH, height: HEIGHT)
    when :play      then PlayScene.new(width: WIDTH, height: HEIGHT)
    when :game_over then GameOverScene.new(width: WIDTH, height: HEIGHT, score: score)
    end
  end
end

game = RGame::Game.new(
  root: Root.new,
  caption: 'Example 14 - Asteroids',
  width: WIDTH,
  height: HEIGHT,
  media_root: MEDIA,
  # Physical ids, not another layer of names. Each action lists every input that
  # triggers it, keyboard and pad together — a device only answers for its own
  # kind, so one table serves both.
  #
  # `thrust` binds the right trigger rather than the stick's y axis, because
  # that axis is positive *downwards* and thrust is forward; see InputMap's
  # note on stick signs. `:ui_confirm` is not declared at all — it comes from
  # the universal set every map is merged over.
  input_map: RGame::Engine::InputMap.new(
    turn: { axis: [Controls::KEY_LEFT, Controls::KEY_RIGHT], stick: Controls::AXIS_LEFT_X },
    thrust: { axis: [Controls::KEY_DOWN, Controls::KEY_UP], stick: Controls::AXIS_TRIGGER_RIGHT },
    fire: { buttons: [Controls::KEY_SPACE, Controls::PAD_A] }
  )
)

# Bind ids to assets the game's own manager loads. This scene names things by
# id rather than by path, so the ids have to be registered; example 15 names
# paths instead and registers nothing.
game.renderer.register_image(:space,  game.assets.image('space.png'))
game.renderer.register_image(:ship,   game.assets.image('example 09/player.png'))
game.renderer.register_image(:rock,   game.assets.image('example 09/rock_000.png'))
game.renderer.register_image(:bullet, game.assets.image('example 09/bullet.png'))

game.audio.register_sound(:shoot, game.assets.sound('example 09/shoot.ogg'))
game.audio.register_sound(:boom,  game.assets.sound('example 09/boom.ogg'))
game.audio.register_sound(:hurt,  game.assets.sound('example 09/hurt.ogg'))
game.audio.register_sound(:blip,  game.assets.sound('example 09/blip.ogg'))
game.audio.register_music(:heartbeat, game.assets.song('example 09/heartbeat.ogg'))
RGame::Engine::AudioDirector.new(game.audio).subscribe

game.start
