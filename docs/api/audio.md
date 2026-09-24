# Audio

rgame plays sound through three classes. `Audio` is the sound device. A `Sample`
is a short sound that can play over itself. A `Song` is a long sound streamed
from disk.

**A scene in an `RGame::Game` never touches these classes.** It plays sound
through the [`AudioOut`](#audioout--the-system-a-node-plays-sound-through)
system, for example `system!(RGame::Engine::AudioOut).play_sound('hit.ogg')`.
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
music.resume     # from where it stopped
```

A song streams from its file as it plays. A three-minute track costs a buffer,
not forty megabytes.

**A song is one voice.** Playing a song that is already playing restarts it from
the beginning, and so does playing it after `stop`. `resume` carries on where
`stop` left it, so `stop` then `resume` is a pause. A song that ran to its end
resumes from the top.

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
audio.play_music('theme.ogg')           # loops
audio.set_music_volume('theme.ogg', 0.5)
audio.pause_music
audio.resume_music
audio.stop_music
audio.stop_music('theme.ogg')           # that song, whichever is current
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

**A game wires none of this.** `RGame::Game` mounts an
[`AudioOut`](#audioout--the-system-a-node-plays-sound-through) holding its device
on the root when it starts, so a scene that plays a sound is heard with no setup.

**`play_music` never restarts a song that is playing.** Asking for the track
already playing leaves it playing. A scene that repeats the request each time it
is entered never restarts the music mid-loop.

**The song `play_music` was last asked for is the current song**, even when it
was already playing. `stop_music` with no id stops it, and `pause_music` and
`resume_music` act on it. The engine keeps no process-wide "current song",
because one song at a time is a game's policy. **`play_music` with a different
track does not stop the previous one**, so both play. To switch tracks, call
`stop_music` first, or fade between them with
[`AudioOut#crossfade`](#fades). You stop a `Song` you started by hand yourself. `stop_music` with nothing playing does
nothing.

**`stop_music(id)` stops the song the id names**, and forgets the current song
only when it is that one. `set_music_volume(id, volume)` sets the song's own
volume, as `Song#volume=` does, and `AudioOut` fades a song with it.

**`pause_music` stops the current song where it is**, and `resume_music` carries
on from there. `resume_music` does nothing unless a song is paused, and
`play_music` asked for the paused song starts it from the top.

## Categories

```ruby
audio.register_sound(:line, app.assets.sound('line.ogg'), category: :voice)
audio.register_music(:rain, app.assets.song('rain.ogg'), category: :ambience)

audio.set_category_volume(:music, 0.7)
audio.set_category_volume(:voice, 0.8)
audio.category_volume(:effects)   # => 1.0
```

**A category is a volume that a set of sounds share**, such as the one a
settings screen offers for music. Every song plays under `:music` and every
sample under `:effects`, unless it was registered under another name. A category
volume multiplies each sound's own volume and leaves it as it was, and the
device's `volume` multiplies over all of them.

**A game names its own categories** with `category:` when it registers a sound.
The first registration under a name creates it, and a sound registered again
plays under the last name given. The device holds sixteen: `:music`, `:effects`
and fourteen more. The seventeenth name raises `ArgumentError`.

**A name no sound was registered under raises `KeyError`**, from
`category_volume` and `set_category_volume` alike, so a mistyped category fails
instead of changing nothing. A category is named by a Symbol; anything else
raises `TypeError`. A sound played by its path and never registered plays under
`:music` or `:effects`.

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

Every volume behaves the same way, whether the device's, a category's, a
sample's or a song's:

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
small. It also lacks positional and 3D audio, effects and filters, seeking,
per-play handles, playback position and recording. `AudioOut` fades music but
not samples, and has no ducking: nothing lowers the music while a voice line
plays.

## `AudioOut` — the system a node plays sound through

**`RGame::Engine::AudioOut` is a component on the root that holds the sound
device, and the clock its music fades on.** A node reaches it with
[`Node2D#system!`](systems.md#looking-a-system-up):

```ruby
out = system!(RGame::Engine::AudioOut)
out.play_sound(:boom)
out.play_music(:theme)                # at full volume
out.play_music(:theme, fade: 0.8)     # up from silence over 0.8 s
out.stop_music(fade: 0.5)             # down to silence, then stopped
out.crossfade(:battle, over: 1.2)     # :theme down while :battle comes up
out.pause_music
out.resume_music
out.set_category_volume(:music, 0.7)
out.category_volume(:music)
out.fading?                           # a song on its way up or down
```

`play_sound`, the two category calls, and `play_music` and `stop_music` without
a fade forward to the device. Ids, looping and what `stop_music` stops work as
this page describes for `Audio`, and without a fade the device receives exactly
the one call it would receive from a scene calling it directly. `AudioOut` calls
the device by method name, so the engine layer never names `RGame::Core::Audio`.

### Fades

**A fade is the song's own volume, set once a tick.** `AudioOut` sets it with
`Audio#set_music_volume` from its `_update`, so a fade runs on the game's clock.
Nothing spreads a step across the frames of a tick: a one-second fade moves the
volume in sixty steps of 1/60.

- `play_music(id, fade:)` sets the song to silence, plays it, and raises it to
  full volume over `fade` seconds.
- `stop_music(fade:)` lowers the current song to silence over `fade` seconds and
  stops it on the tick it arrives.
- `crossfade(id, over:)` lowers the current song while it raises `id` over the
  same time, and stops the old song once it is silent. With no current song it
  is a fade in.

A song that `AudioOut` stops or fades out plays at full volume the next time.
`fade:` and `over:` take 0 or more seconds; anything else raises `ArgumentError`.

This runs headless, with a stand-in for the device that keeps each song's
volume, the way rgame's own specs drive it:

```ruby
require 'rgame'

# Keeps the volume each song was last given, and plays nothing.
class Mixer
  attr_reader :volumes

  def initialize = @volumes = {}
  def play_music(id) = @volumes[id] ||= 1.0
  def stop_music(_id = nil) = nil
  def set_music_volume(id, volume) = @volumes[id] = volume
end

mixer = Mixer.new
root = RGame::Engine::Node2D.new
out = root.add_component(RGame::Engine::AudioOut.new(mixer))
root.enter_tree

out.play_music(:theme)
out.crossfade(:battle, over: 1.0)
root.update(0.25)
mixer.volumes   # => {theme: 0.75, battle: 0.25}
out.fading?     # => true
root.update(0.75)
mixer.volumes   # => {theme: 1.0, battle: 1.0} — :theme stopped, at full for next time
out.fading?     # => false
```

**`AudioOut` tracks two songs: the current one, and one on its way out.** Four
rules follow from that:

- **Asking for the song on its way out brings it back up from where it is.**
  `play_music` with a fade, or `crossfade`, raises it again without starting it
  from the top. A crossfade asked for back the other way turns both songs round.
- **A crossfade begun before the last one ended** stops the song still on its
  way out at once, and brings the one that was coming in down from where it is.
- **`stop_music` without a fade** stops the song on its way out too.
- **`play_music` with another song and no crossfade** leaves the current one
  playing, as `Audio#play_music` does. If the current song was fading in, it
  goes to full volume at once.

**A fade outlives the scene that asked for it.** `AudioOut` is on the root, so a
scene that fades its music out as it leaves the tree still fades. For the same
reason, pausing a scene does not pause its music or a fade.

**`pause_music` holds the current song and its fade where they are**, and
`resume_music` carries both on. A song on its way out of a crossfade stops at
once. Stepping a fade, and holding one, allocates nothing.

**`RGame::Game` mounts it in `start`**, holding `Game#audio`: the device `App`
builds, or the one passed as `audio:`. A node that is not in the tree, or a tree
with no `AudioOut`, makes `system!` raise `KeyError` naming `AudioOut`. A node
without a tree cannot play a sound, so a quest effect or other code that is not
a node needs a node handed to it.

**A headless spec mounts one on a recording device.** rgame's own suite does it
with the `FakeAudio` in `spec/support/`, which is checked against the same
contract as the real device:

```ruby
root.add_component(RGame::Engine::AudioOut.new(FakeAudio.new))
```
