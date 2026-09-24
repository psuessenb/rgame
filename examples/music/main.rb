# frozen_string_literal: true

# Music — a looping track that fades in and out, pauses, and has a volume per
# category.
#
# Run it:
#
#   ruby examples/music/main.rb
#
# **Enter** fades the track in over a second and **Escape** fades it out. **P**
# pauses it and resumes it, holding a fade where it is. **Up** and **Down** turn
# the music up and down a tenth at a time, and **Left** and **Right** do the same
# for the effects, with a blip on each press so there is an effect to hear. It
# exercises:
#   - Engine::AudioOut — `play_music` and `stop_music` with `fade:`, pause and
#     resume, and `set_category_volume`, mounted by RGame::Game;
#   - Core::Song — a streamed track with one voice, which can be stopped,
#     resumed and asked whether it is playing, named by its path;
#   - Engine::Tween with `loop: true` — the playhead, which starts again at the
#     loop point.
#
# ## A fade is a volume set once a tick
#
# `AudioOut` raises the song's own volume a sixtieth at a time, from its
# `_update`, so a one-second fade is sixty steps. Nothing smooths a step across
# the frames between two ticks. **Whether you can hear the steps is what this
# example is for:** listen to a fade with the music turned up, over a quiet
# passage, and listen for a buzz or a stair-step under it.
#
# A fade in starts the track from the top. Press Escape and then Enter before
# the fade out ends, and the track comes back up from where it is, without
# starting again. Press Enter while it plays and nothing happens: a scene that
# asks for its music every time it is entered never restarts it.
#
# ## Two volumes that do not touch
#
# The track plays under the `:music` category and the blip under `:effects`.
# Each category's volume multiplies the sounds in it, so turning the music down
# leaves the blip as loud as it was.
#
# ## What it does not show
#
# A crossfade needs two tracks, and this example ships one. `docs/api/audio.md`
# shows `AudioOut#crossfade`.
#
# ## The bar is state, not a clock
#
# Nothing on a draw path reads a clock (see "`draw` renders state"). So the bar
# is a playhead accumulated from `dt` in `update` while the track plays, and it
# stops while the track is paused. It says how long this scene has played the
# track, which is close enough to watch the 24 s loop point go past and listen
# for whether the wrap clicks.

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

WIDTH  = 640
HEIGHT = 480
ASSETS = File.expand_path('../assets', __dir__)
LOCALES = File.expand_path('locales', __dir__) # the text on screen: locales/en.yml

LOOP_SECONDS = 24.05 # the length of music.ogg; see examples/assets/README.md
TRACK = 'music.ogg'
BLIP = 'blip.ogg'
FADE = 1.0 # seconds

class Scene < RGame::Engine::Node2D
  BAR_X = 60
  BAR_Y = 260
  BAR_W = 520
  BAR_H = 26
  RAIL = RGame::Util::Color.new(40, 48, 66)
  FILL = RGame::Util::Color.new(120, 200, 255)
  FILL_PAUSED = RGame::Util::Color.new(90, 110, 140)
  STATE = {
    stopped: RGame::Engine::Text.new('status.stopped'),
    rising: RGame::Engine::Text.new('status.rising'),
    playing: RGame::Engine::Text.new('status.playing'),
    falling: RGame::Engine::Text.new('status.falling'),
    paused: RGame::Engine::Text.new('status.paused')
  }.freeze

  def initialize
    super
    @state = :stopped
    @held = false
    @music = 10 # tenths
    @effects = 10
    @playhead = RGame::Engine::Tween.new(LOOP_SECONDS, loop: true)
    @help = RGame::Engine::Text.new('help.keys')
    @help_volume = RGame::Engine::Text.new('help.volume')
    @volumes = RGame::Engine::Text.new('status.volumes', :music, :effects)
  end

  def _control(actions)
    if actions.pressed?(:pause)
      toggle_pause
    elsif !@held
      fade_in if actions.pressed?(:ui_confirm)
      fade_out if actions.pressed?(:ui_cancel)
    end
    turn_music(1) if actions.pressed?(:ui_up)
    turn_music(-1) if actions.pressed?(:ui_down)
    turn_effects(1) if actions.pressed?(:ui_right)
    turn_effects(-1) if actions.pressed?(:ui_left)
  end

  def _update(dt)
    return if @held || @state == :stopped

    settle unless out.fading?
    @playhead.update(dt) unless @state == :stopped
  end

  def _draw(renderer, _view)
    renderer.text(@help, 12, 12)
    renderer.text(@help_volume, 12, 34)
    renderer.text(@held ? STATE[:paused] : STATE[@state], 12, 68)
    renderer.text(@volumes.with(music: @music * 10, effects: @effects * 10), 12, 90)

    # Where the playhead sits inside one pass of the loop. It wraps at
    # LOOP_SECONDS, so the bar resetting is the loop point going past.
    renderer.rect(BAR_X, BAR_Y, BAR_W, BAR_H, color: RAIL)
    renderer.rect(BAR_X, BAR_Y, BAR_W * @playhead.progress, BAR_H, color: @held ? FILL_PAUSED : FILL)
  end

  private

  def out = system!(RGame::Engine::AudioOut)

  # Unconditional on purpose: AudioOut knows whether the track is already
  # playing, fading in or on its way out, and does the right thing for each.
  def fade_in
    out.play_music(TRACK, fade: FADE)
    @state = :rising unless @state == :playing
  end

  def fade_out
    return if @state == :stopped

    out.stop_music(fade: FADE)
    @state = :falling
  end

  # A fade that has run its course: the track is up, or it has stopped.
  def settle
    if @state == :falling
      @state = :stopped
      @playhead.restart
    else
      @state = :playing
    end
  end

  def toggle_pause
    return if @state == :stopped

    @held ? out.resume_music : out.pause_music
    @held = !@held
  end

  def turn_music(by)
    @music = (@music + by).clamp(0, 10)
    out.set_category_volume(:music, @music / 10.0)
  end

  def turn_effects(by)
    @effects = (@effects + by).clamp(0, 10)
    out.set_category_volume(:effects, @effects / 10.0)
    out.play_sound(BLIP)
  end
end

game = RGame::Game.new(
  root: Scene.new,
  caption: 'Music',
  width: WIDTH,
  height: HEIGHT,
  media_root: ASSETS,
  locales: LOCALES,
  # P and Start are free in the default map. The arrows also move a hero and a
  # menu, and nothing here reads either.
  input_map: RGame::Engine::InputMap.default.merge(
    pause: { buttons: [RGame::Util::Controls::KEY_P, RGame::Util::Controls::PAD_START] }
  )
)

game.start
