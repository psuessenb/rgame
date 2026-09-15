# Audio

rgame plays sound through three classes. `Audio` is the sound device. A `Sample`
is a short sound that can play over itself. A `Song` is a long sound streamed
from disk.

**A scene in an `RGame::Game` never touches these classes.** It emits on
[`AudioBus`](toolbox.md#audiobus--decoupled-audio-facts), for example
`RGame::Engine::AudioBus.play_sound('hit.ogg')`, and the game's director plays it.
The example below drives the device directly from a plain `App`:

```ruby
require 'rgame/core'

class MyGame < RGame::Core::App
  def initialize
    super(width: 800, height: 600, caption: 'demo')
    @hit = audio.sample('assets/hit.ogg')
    @music = audio.song('assets/theme.ogg')
    @music.play(looping: true)
  end

  def button_down(id)
    @hit.play if id == RGame::Util::Controls::KEY_SPACE
  end
end

MyGame.new.run
```

rgame decodes Ogg Vorbis and WAV, and nothing else. See
[What is not here](#what-is-not-here).

## The device

```ruby
audio = app.audio          # the one a game uses
audio.backend              # => "PulseAudio"
audio.volume               # => 1.0
audio.volume = 0.8
```

**Use `App#audio`.** An app opens the device on first use and hands it the app's
asset manager. That manager lets `play_sound('hurt.ogg')` name a file.
`RGame::Core::Audio.new` builds a standalone device for a tool or a spec. It has
no manager, so it plays only objects it receives or has registered.

**The device is not tied to a window.** Unlike an `Image`, a sound belongs to no
GL context. It survives a window resize or rebuild, and `Audio.new` takes no app.
An app holds one device only because a program wants exactly one, like its asset
manager.

**A machine without sound hardware still gets a working device.** It opens a
null backend and plays silence instead of raising, and `#backend` returns
`"Null"`. A game should run on a CI runner, in a container, or on a laptop with
its sound card off. Crashing at startup over sound would be the worse failure.
Ask `#backend` if your game needs to know; nothing else changes.

`#volume` is the master volume. The device multiplies it into everything it
plays.

## Samples

```ruby
hit = audio.sample('assets/hit.ogg')
hit.volume = 0.5
hit.play
hit.play    # a second voice, over the first
```

A sample decodes once, into memory, and plays as often as you like. **Playing a
sample that is already sounding layers another voice over it.** It does not
restart. A fast run of footsteps therefore sounds like footsteps, not one
stuttering step.

A sample is fire-and-forget. A single play has no handle and cannot be stopped.
Volume belongs to the sample and reaches every voice it has out, including those
already sounding.

**Use samples for short sounds only.** A sample holds its whole decoded length in
memory, roughly 10 MB per minute of CD-quality stereo. Put music in a `Song`.

Two samples loaded from the **same path** share one decoded copy. Loading a file
a second time costs nothing.

## Songs

```ruby
music = audio.song('assets/theme.ogg')
music.play(looping: true)
music.playing?   # => true
music.volume = 0.6
music.stop
```

A song streams from its file as it plays. A three-minute track costs a buffer,
not forty megabytes.

**A song is one voice.** Playing a song that is already playing restarts it from
the beginning, and so does playing it after `stop`. Songs cannot pause: `stop`
then `play` starts from the top.

`#playing?` and `#looping?` report what the song was last told to do.
`#looping?` is a flag, not a count.

**The engine allows several songs at once**; a crossfade needs two. A game that
wants one song at a time stops the old one before starting the next.

## Playing by id

**Gameplay names a sound; it does not hold one.** Drawing follows the same rule,
because a scene may not hold a `Sample`. `examples/sound` and `examples/music`
show both kinds. The first fires and layers a sample from a button. The second
loops, stops and restarts a song.

```ruby
audio.play_sound('hurt.ogg')
audio.play_music('theme.ogg')   # loops
audio.stop_music
```

**Ids come in two kinds, the same two the renderer uses.** A **String is a
root-relative path**. The device resolves it through the asset manager on first
use and remembers the result. A **Symbol is a name the game chose**, and only
registration binds one:

```ruby
audio.register_sound(:hit, app.assets.sound('hurt.ogg'))
audio.register_music(:theme, app.assets.song('theme.ogg'))
audio.play_sound(:hit)
audio.play_music(:theme)
```

Registration also *overrides* a path. A game uses that to bind a sound it built
instead of loaded. An id that is neither registered nor resolvable raises
`KeyError`. `nil` raises `TypeError`, because an asset that resolved to nothing
is a different bug from a mistyped name.

**The device caches every resolution, and must.** `play_music` asks the song
whether it is already playing. Resolving one path to two `Song` objects would
defeat that check and restart the track on every request.

**A game wires none of this.** When `RGame::Game` starts, it subscribes an
[`AudioDirector`](toolbox.md) to the global `AudioBus`. When the loop ends, it
unsubscribes it. A scene that emits on the bus is heard with no setup. The engine
owns both steps because each failure is invisible. Without a director, the tree
runs and the events fire, but nothing plays. A director left on the bus keeps
the device, the asset manager and the whole `App` alive for the life of the
process. A single game never notices, but a process running two games does.

**`play_music` is idempotent.** Asking for the track already playing does
nothing. A scene that repeats the request each time it is entered never restarts
the music mid-loop.

**`stop_music` stops the song `play_music` most recently started**, not whatever
is sounding. The engine keeps no process-wide "current song", because one song at
a time is a game's policy. **`play_music` with a different track does not stop the
previous one**, so both play. To switch tracks, call `stop_music` first. You stop
a `Song` you started by hand yourself. `stop_music` with nothing playing does
nothing.

## Loading and failure

```ruby
audio.sample(path)   # => RGame::Core::Sample
audio.song(path)     # => RGame::Core::Song

RGame::Core::Sample.new(audio, path)   # the same thing
RGame::Core::Song.new(audio, path)
```

**Prefer `audio.sample` and `audio.song`.** They read in the direction the
objects depend, and a stand-in device can offer them, while `Sample.new` cannot
be faked (see [Testing](#testing)).

`audio.sample`, `audio.song` and the two constructors resolve a relative path
against the working directory, and cache nothing. `app.assets.sound(path)` and
`app.assets.song(path)` resolve against `media_root` and cache, and a String id
passed to `play_sound` or `play_music` goes through them.

A file the engine cannot read or decode raises `RGame::Core::Sample::LoadError`
or `RGame::Core::Song::LoadError`, naming the file. Both inherit from
`StandardError`, so an ordinary `rescue` catches them:

```ruby
@music = begin
  audio.song('assets/theme.ogg')
rescue RGame::Core::Song::LoadError => e
  warn "no music: #{e.message}"
  nil
end
```

The engine checks the **content, not the extension**. It refuses a text file
named `.ogg`.

## Volume

Every volume behaves the same way, whether the device's, a sample's or a song's:

| Value | Effect |
|---|---|
| `1.0` | unchanged, the default |
| `0.0` … `1.0` | quieter |
| above `1.0` | amplified; clipping is yours to avoid |
| below `0.0` | clamped to `0.0` |

**A negative volume clamps to silence instead of raising.** A fader driven by a
slider or an easing curve undershoots all the time, and silence is the useful
answer. A true negative volume would invert the phase, which sounds *louder*.

The mixer stores volumes as 32-bit floats, so `0.8` reads back as
`0.800000011920929`. Compare with a tolerance, not with `==`.

## What it costs

**Nothing needs freeing.** A sample or song releases its memory when it is
collected. Each keeps its device alive while it exists. Dropping your reference
to the `Audio` while a sound remains is safe, in either order.

`RGame::Core::Audio.debug_live_sounds` returns how many samples and songs exist.
It serves tests, not gameplay.

## Testing

**Audio follows the drawing pattern.** The engine layer receives a device and
calls it by method name, never by class. A headless spec can substitute a device
that makes no sound and records every call.

rgame's own suite uses `spec/support/fake_audio.rb` as that stand-in.
`spec/support/shared_examples/an_audio_server.rb` defines the contract, and both
the fake and the real device run against it. A fake that drifted from the device
would keep `rake spec` green while the game played nothing.

```ruby
audio = FakeAudio.new
audio.sample('hit.ogg').play

expect(audio.played?('hit.ogg')).to be(true)
expect(audio.calls.map(&:name)).to eq(%i[sample sample_play])
```

That spec loads no file, opens no device and needs no sound card.

## What is not here

rgame audio has no MP3 or FLAC; it decodes Vorbis and WAV only, to keep the gem
small. It also lacks positional and 3D audio, effects and filters, fades,
pausing, seeking, per-play handles, playback position and recording.
