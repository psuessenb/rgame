# frozen_string_literal: true

# Music — a looping track, started and stopped.
#
# Run it:
#
#   ruby examples/music/main.rb
#
# Enter or Space starts it; Escape stops it. Press start again while it is
# already playing and **nothing happens** — that is deliberate, and the reason
# is below. It exercises:
#   - Core::Audio#register_music and Core::Song — a streamed track with one
#     voice, which can be stopped and asked whether it is playing;
#   - Engine::AudioBus play_music / stop_music;
#   - Engine::AudioDirector, the same one `examples/sound` uses.
#
# ## A Song is not a Sample
#
# The two types exist so that this distinction is in the type rather than in a
# convention. A `Sample` (see `examples/sound`) is decoded up front and gets a
# fresh voice per play, so it layers and `playing?` would be meaningless. A
# `Song` is *streamed* and has exactly one voice: it can be stopped, and it can
# be asked whether it is running.
#
# ## Starting it twice does not restart it
#
# `Audio#play_music` returns early when the song is already playing. That is not
# a nicety — a scene that emits `play_music` from `on_add` every time it is
# entered would otherwise chop the track back to zero each time the player
# walked through a door.
#
# **You confirm that by ear, not from this window.** Press Enter again while it
# is playing: the bar below carries on, but that only proves *this scene* did
# not reset its own timer. Whether the audio restarted is a fact about the
# device, and the only honest way to check it is to listen for the track
# jumping back to its opening bar.
#
# ## The bar is state, not a clock
#
# Nothing on a draw path reads a clock — `draw` is not called on a schedule and
# a wall clock cannot be paused or reproduced (CLAUDE.md, "`draw` renders
# state"). So the seconds below are accumulated from `dt` in `update`. It is a
# rough playhead, not a reading off the song: it says how long ago this scene
# *asked* for music, which is close enough to watch the 24s loop point go past
# and listen for whether the wrap clicks. `tools/shrink_ogg.c` measures the seam
# at 2.3% of the music's own largest step *and* the silence at each end at zero
# — this is where you find out whether those numbers were telling the truth.

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

WIDTH  = 640
HEIGHT = 480
ASSETS = File.expand_path('../assets', __dir__)

LOOP_SECONDS = 24.05 # the length of music.ogg; see examples/assets/README.md

class Scene < RGame::Engine::Node2D
  BAR_X = 60
  BAR_Y = 260
  BAR_W = 520
  BAR_H = 26
  TRACK  = RGame::Util::Color.new(40, 48, 66)
  FILL   = RGame::Util::Color.new(120, 200, 255)

  def initialize
    super
    @playing = false
    @elapsed = 0.0
    @status = 'stopped — press Enter'
  end

  def on_control(actions)
    start if actions.pressed?(:ui_confirm)
    stop if actions.pressed?(:ui_cancel)
  end

  def on_update(dt)
    return unless @playing

    @elapsed += dt
  end

  def on_draw(renderer, _view)
    renderer.text('Enter / A starts, Escape / B stops', 12, 12)
    renderer.text(@status, 12, 34)

    # Where the playhead sits inside one pass of the loop. It wraps at
    # LOOP_SECONDS, so the bar resetting is the loop point going past.
    renderer.rect(BAR_X, BAR_Y, BAR_W, BAR_H, color: TRACK)
    position = @elapsed % LOOP_SECONDS
    renderer.rect(BAR_X, BAR_Y, BAR_W * (position / LOOP_SECONDS), BAR_H, color: FILL)
  end

  private

  # The bus call is unconditional on purpose: this node has no idea whether the
  # track is already going, and does not need one. The guard lives in
  # Audio#play_music, which owns the state that answers it.
  #
  # `@playing` below is *not* that state duplicated — it only drives the bar and
  # the label, and it is why the bar keeps running on a second press rather than
  # proving anything about the device.
  def start
    RGame::Engine::AudioBus.play_music(:theme)
    return if @playing

    @playing = true
    @status = 'playing — press Enter again; listen for whether it restarts'
  end

  def stop
    RGame::Engine::AudioBus.stop_music
    @playing = false
    @elapsed = 0.0
    @status = 'stopped — press Enter'
  end
end

game = RGame::Game.new(
  root: Scene.new,
  caption: 'Music',
  width: WIDTH,
  height: HEIGHT,
  media_root: ASSETS
)

game.audio.register_music(:theme, game.assets.song('music.ogg'))
RGame::Engine::AudioDirector.new(game.audio).subscribe

game.start
