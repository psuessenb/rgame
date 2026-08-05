# frozen_string_literal: true

# A sound device that makes no sound and remembers everything.
#
# This is what a headless spec hands a scene in place of the real thing. Nothing
# in the engine layer names an audio class — it is given a device and calls it
# by method name — so nothing can tell the difference, and a spec gets to assert
# on *what was played* rather than on what came out of the speakers:
#
#   audio = FakeAudio.new
#   scene.audio = audio
#   scene.update(1.0 / 60)
#
#   expect(audio.played?('hit.ogg')).to be(true)
#   expect(audio.calls.map(&:name)).to eq(%i[sample_play song_play])
#
# Every sample and song it makes reports back to it, so one log covers the whole
# subsystem — a spec never has to hold on to the individual sounds to find out
# what happened to them.
#
# Paths are opaque. The fake never opens one, so a spec can use whatever names
# its assertions read best with, `:hit` as readily as 'assets/hit.ogg'.
#
# It is checked against the same shared contract as the real device (see
# fake_audio_spec.rb). If the two drift, `rake spec` would stay green while the
# game played nothing, which is exactly the failure the headless/Core split
# cannot catch on its own.
class FakeAudio
  # One recorded call. `path` is the sound it happened to, or nil for the ones
  # that happened to the device itself.
  Call = Struct.new(:name, :path, :args)

  # The two call names #played? counts. A frozen constant rather than a literal
  # in the method, so asking the question allocates nothing.
  PLAYS = %i[sample_play song_play].freeze

  attr_reader :calls, :volume

  def initialize
    @calls = []
    @volume = 1.0
  end

  def backend = 'Fake'

  def volume=(value)
    @volume = FakeAudio.clamp(value)
    remember(:volume, nil, [@volume])
  end

  def sample(path)
    remember(:sample, path, [])
    FakeSample.new(self, path)
  end

  def song(path)
    remember(:song, path, [])
    FakeSong.new(self, path)
  end

  # --- what a spec asks afterwards ----------------------------------------

  def calls_to(name) = @calls.select { |call| call.name == name }

  # Whether anything was played at all, or a particular sound was. Covers both
  # samples and songs, because a spec asking "did the hit sound happen" does
  # not care which kind it was.
  def played?(path = nil)
    plays = @calls.select { |call| PLAYS.include?(call.name) }
    path.nil? ? plays.any? : plays.any? { |call| call.path == path }
  end

  # Forgets everything, so one spec can drive several frames.
  def clear
    @calls.clear
    self
  end

  # Negative volumes clamp to silence and volumes above one are allowed, the
  # same way the real mixer treats them — see the 'an audio server' contract for
  # why. Shared by the device and both kinds of sound.
  def self.clamp(value) = value.negative? ? 0.0 : value

  def remember(name, path, args)
    @calls << Call.new(name, path, args)
    self
  end
end

# A short sound from a FakeAudio. Playing it records; nothing else happens.
class FakeSample
  attr_reader :path, :volume

  def initialize(audio, path)
    @audio = audio
    @path = path
    @volume = 1.0
  end

  def play
    @audio.remember(:sample_play, @path, [])
    self
  end

  def volume=(value)
    @volume = FakeAudio.clamp(value)
    @audio.remember(:sample_volume, @path, [@volume])
  end
end

# A long sound from a FakeAudio. Unlike a sample it has state a spec can read
# back, because the real one does: a song is one voice, and whether it is
# playing is the question a scene asks about it.
class FakeSong
  attr_reader :path, :volume

  def initialize(audio, path)
    @audio = audio
    @path = path
    @volume = 1.0
    @playing = false
    @looping = false
  end

  def play(looping: false)
    @looping = looping
    @playing = true
    @audio.remember(:song_play, @path, [looping])
    self
  end

  def stop
    @playing = false
    @audio.remember(:song_stop, @path, [])
    self
  end

  def playing? = @playing
  def looping? = @looping

  def volume=(value)
    @volume = FakeAudio.clamp(value)
    @audio.remember(:song_volume, @path, [@volume])
  end
end
