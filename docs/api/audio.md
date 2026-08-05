# Audio

```ruby
require 'rgame/core'

class MyGame < RGame::Core::App
  def initialize
    super(width: 800, height: 600, caption: 'demo')
    @audio = RGame::Core::Audio.new
    @hit = @audio.sample('assets/hit.ogg')
    @music = @audio.song('assets/theme.ogg')
    @music.play(looping: true)
  end

  def button_down(id)
    @hit.play if id == RGame::Util::Controls::KEY_SPACE
  end
end
```

Three classes. `Audio` is the sound device; `Sample` is a short sound played
over itself; `Song` is a long one streamed from disk.

Ogg Vorbis and WAV are the formats. Nothing else — see [What is not
here](#what-is-not-here).

## The device

```ruby
audio = RGame::Core::Audio.new
audio.backend    # => "PulseAudio"
audio.volume     # => 1.0
audio.volume = 0.8
```

**It takes no app.** Sound is not tied to a window: it survives one being
resized or recreated, and there is no GL context involved. One device for the
program is the normal arrangement.

**A machine with no sound hardware still gets a working device.** It opens a
null backend and plays silently rather than raising, and `#backend` returns
`"Null"`. That is deliberate — a game should run on a CI runner, in a container,
or on a laptop with the sound card switched off, and crashing at startup over
something nobody asked for is the worse failure. If your game wants to know, ask
`#backend`; nothing else changes.

`#volume` is the master volume, multiplied into everything the device plays.

## Samples

```ruby
hit = audio.sample('assets/hit.ogg')
hit.volume = 0.5
hit.play
hit.play    # a second voice, over the first
```

A sample is decoded once, into memory, and played as often as you like.
**Playing one that is already sounding layers another voice over it** rather
than restarting it — which is what makes a fast run of footsteps sound like
footsteps instead of one stuttering step.

There is no handle for an individual play, and no way to stop one: a sample is
fire-and-forget. Volume belongs to the sample and reaches every voice it has
out, including the ones already sounding.

Keep samples for short sounds. A sample holds its whole decoded length in
memory — measured at roughly 10 MB per minute of CD-quality stereo — so a music
track belongs in a `Song`.

Two samples loaded from the **same path** share one decoded copy, so loading a
file twice costs nothing the second time.

## Songs

```ruby
music = audio.song('assets/theme.ogg')
music.play(looping: true)
music.playing?   # => true
music.volume = 0.6
music.stop
```

A song is streamed from the file as it plays, so a three-minute track costs a
buffer rather than forty megabytes.

**A song is one voice.** Playing one that is already playing restarts it from
the beginning; so does playing it after `stop`. There is no pause — `stop` then
`play` is "from the top", not "resume".

`#playing?` and `#looping?` report what the song was last told to do.
`#looping?` is the flag, not a count.

**"One song at a time" is your rule, not the engine's.** Two songs can play at
once, which is what a crossfade is; if a game wants only one, it stops the old
one before starting the new one.

## Loading and failure

```ruby
audio.sample(path)   # => RGame::Core::Sample
audio.song(path)     # => RGame::Core::Song

RGame::Core::Sample.new(audio, path)   # the same thing
RGame::Core::Song.new(audio, path)
```

Both forms exist. Prefer `audio.sample` — it reads in the direction the objects
depend, and a stand-in device can offer it while `Sample.new` cannot (see
[Testing](#testing)).

A file that cannot be read, or that is not a format the engine decodes, raises
`RGame::Core::Sample::LoadError` or `RGame::Core::Song::LoadError`, naming the
file. Both are `StandardError`, so an ordinary `rescue` catches them:

```ruby
@music = begin
  audio.song('assets/theme.ogg')
rescue RGame::Core::Song::LoadError => e
  warn "no music: #{e.message}"
  nil
end
```

The decision is made by **content, not by extension** — a text file named
`.ogg` is refused.

## Volume

Every volume — the device's, a sample's, a song's — behaves the same way:

| Value | Effect |
|---|---|
| `1.0` | unchanged, the default |
| `0.0` … `1.0` | quieter |
| above `1.0` | amplified; clipping is yours to avoid |
| below `0.0` | clamped to `0.0` |

Negative is clamped rather than refused because a fader driven by a slider or an
easing curve undershoots constantly, and silence is the meaningful answer — a
negative volume would phase-invert the samples, which is *louder*.

Volumes are 32-bit floats inside the mixer, so `0.8` reads back as
`0.800000011920929`. Compare with a tolerance, not with `==`.

## What it costs

Nothing needs freeing. A sample or a song releases what it holds when it is
collected, and each one keeps its device alive for as long as it exists — so
dropping your reference to the `Audio` while a sound is still around is safe,
in either order.

`RGame::Core::Audio.debug_live_sounds` reports how many samples and songs exist.
It is there for tests, not for gameplay.

## Testing

Audio follows the same pattern as drawing: the engine layer is handed a device
and calls it by method name, never by class, so a headless spec can substitute
one that makes no sound and records everything.

`spec/support/fake_audio.rb` is that stand-in, and
`spec/support/shared_examples/an_audio_server.rb` is the interface both it and
the real device are run against — so the fake cannot drift into describing an
engine that no longer exists.

```ruby
audio = FakeAudio.new
audio.sample('hit.ogg').play

expect(audio.played?('hit.ogg')).to be(true)
expect(audio.calls.map(&:name)).to eq(%i[sample sample_play])
```

Nothing there loads a file, opens a device, or needs a sound card.

## What is not here

MP3 and FLAC (Vorbis and WAV only, to keep the gem small), positional and 3D
audio, effects and filters, fades, pausing, seeking, per-play handles, playback
position, and recording. A play-by-id registry — `play_sound(:hit)` over a set
of loaded samples — belongs to the scene layer and is still to come.
