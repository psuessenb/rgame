# frozen_string_literal: true

# Sound — a sound effect fired by a button, and the seam it travels through.
#
# Run it:
#
#   ruby examples/sound/main.rb
#
# Space (or A on a pad) plays a blip. Press it fast: each press is another
# voice, so they overlap rather than cutting each other off. It exercises:
#   - Core::Sample — a decoded, fire-and-forget effect, named by its path;
#   - Engine::AudioBus — where gameplay says *what happened*;
#   - Engine::AudioDirector — what turns that into playback, subscribed by
#     RGame::Game;
#   - Engine::CachedLabel — a count on screen that costs no String per frame.
#
# ## Why a node does not just call the audio device
#
# It cannot. A node lives in `RGame::Engine`, and that layer may not name
# `RGame::Core` at all — not a require, not a constant. So `Scene#on_control`
# below emits on `AudioBus`, a global signal hub that knows nothing about sound,
# and an `AudioDirector` forwards it to the real device. `RGame::Game` subscribes
# that director when it starts and releases it when the loop ends, so this file
# wires nothing.
#
# That looks like ceremony until you notice what it buys: the same scene runs in
# a headless spec with a recording fake substituted for the device, and the spec
# asserts on *what was asked for* rather than on what came out of a speaker.
# `spec/support/shared_examples/an_audio_server.rb` is the contract both sides
# are held to.
#
# ## A Sample is not a Song
#
# There are two types on purpose. This is a `Sample`: decoded up front, and every
# `play_sound` starts a **new voice** layered over whatever is already sounding.
# It has no `playing?`, because the question has no answer for a sound that may
# be going five times at once. `examples/music` is the other type.
#
# ## Naming a sound is naming a file
#
# `'blip.ogg'` is a path, resolved through the asset manager on first use and
# remembered — the same thing `examples/walk` does with `'hero.json'`. Nothing is
# registered anywhere in this file.
#
# The other id space is a Symbol, which `audio.register_sound(:hit, ...)` binds
# to a sound the game chose the name for, or assembled rather than loaded. Audio
# and the renderer take the same two, so one rule covers both: a String is a
# file, a Symbol is a name.

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

WIDTH  = 640
HEIGHT = 480
ASSETS = File.expand_path('../assets', __dir__)

class Scene < RGame::Engine::Node2D
  RING = RGame::Util::Color.new(120, 200, 255)
  FADE = 3.0        # how fast the flash decays, in units per second
  MIN_R = 18.0      # radius at rest
  GROW  = 90.0      # extra radius at full flash

  def initialize
    super
    @flash = 0.0
    @plays = 0
    # Built once, here, and that is the whole trick: the block below is the only
    # place a String is interpolated, and it runs when the count changes rather
    # than when a frame is drawn. See the note above on_draw.
    @plays_label = RGame::Engine::CachedLabel.new { |plays| "plays: #{plays}" }
  end

  def on_control(actions)
    return unless actions.pressed?(:fire)

    # The whole of "make a noise": a fact, emitted. Nothing here knows whether
    # anything is listening, or what it would play it on.
    RGame::Engine::AudioBus.play_sound('blip.ogg')

    @flash = 1.0
    @plays += 1
  end

  # The flash is state, advanced by dt — not a clock read at draw time. That is
  # the standing rule (CLAUDE.md, "`draw` renders state"), and it is why pausing
  # this node would freeze the ring mid-fade instead of letting it run on.
  def on_update(dt)
    @flash -= dt * FADE
    @flash = 0.0 if @flash.negative?
  end

  # A count, drawn as text, allocating nothing.
  #
  # `"plays: #{@plays}"` written here would build a String on every frame
  # forever, and `Game/NoInterpolationInHotPath` is right to refuse it: a steady
  # 60fps frame that allocates is a GC pause waiting to happen.
  # `Engine::CachedLabel` holds the last string and rebuilds it only when the
  # value it was made from changes, so pressing the key costs one allocation and
  # the thousand frames between presses cost none.
  #
  # **Reach for it rather than inventing a way round the rule.** A label built
  # from something that changes is common enough that the engine owns the
  # answer — see CLAUDE.md, "A label built from a changing value".
  def on_draw(renderer, _view)
    renderer.circle(WIDTH / 2, HEIGHT / 2, MIN_R + (GROW * @flash), color: RING)
    renderer.text('Press Space (or A on a controller) — fast, to hear them overlap', 12, 12)
    renderer.text(@plays_label[@plays], 12, 44)
  end
end

game = RGame::Game.new(
  root: Scene.new,
  caption: 'Sound',
  width: WIDTH,
  height: HEIGHT,
  media_root: ASSETS
)

game.start
