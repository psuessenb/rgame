# frozen_string_literal: true

# Example 14 — Asteroids.
#
# A full small game on the Node2D/Component architecture, exercising it end to end:
#   - three scenes (start → play → game-over) navigated through a SceneStack;
#   - a scene-scoped CollisionWorld system + a root-scoped HighScores system
#     (the two service scopes — see docs/engine/systems.md);
#   - reusable components: Velocity, ScreenWrap, DespawnOffscreen, CircleCollider,
#     Sprite, ThrustController, ActionTrigger;
#   - pooled bullets and rocks (Engine::Pool) with deferred removal (queue_free);
#   - audio via the global AudioBus + AudioDirector.

require_relative '../../lib/son_gosu_game'
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
class Root < Engine::Node2D
  def initialize
    super
    @stack = add_component(Engine::Scene::SceneStack.new)
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

game = SonGosuGame.new(
  root: Root.new,
  caption: 'Example 14 - Asteroids',
  width: WIDTH,
  height: HEIGHT,
  action_map: {
    turn: { axis: %i[left right] },
    thrust: { axis: %i[down up] },
    fire: { button: %i[fire] },
    confirm: { button: %i[confirm] }
  }
)

# Register textures on the renderer the window draws through (exposed by SonGosuGame),
# and wire audio. The window exists after SonGosuGame.new, so asset loading is valid.
assets = Platform::AssetManager.new(root: MEDIA)
game.renderer.register_image(:space,  assets.image('space.png'))
game.renderer.register_image(:ship,   assets.image('example 09/player.png'))
game.renderer.register_image(:rock,   assets.image('example 09/rock_000.png'))
game.renderer.register_image(:bullet, assets.image('example 09/bullet.png'))

audio = Platform::GosuAudio.new
audio.register_sound(:shoot, assets.sound('example 09/shoot.ogg'))
audio.register_sound(:boom,  assets.sound('example 09/boom.ogg'))
audio.register_sound(:hurt,  assets.sound('example 09/hurt.ogg'))
audio.register_sound(:blip,  assets.sound('example 09/blip.ogg'))
audio.register_music(:heartbeat, assets.song('example 09/heartbeat.ogg'))
Engine::AudioDirector.new(audio).subscribe

game.start
