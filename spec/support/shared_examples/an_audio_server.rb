# frozen_string_literal: true

# The audio interface, stated once and run against every implementation.
#
# Sound reaches the engine layer the way drawing does: an object is handed in
# and called by method name, never by class. That makes this method list a real
# interface with more than one implementation — the live device that owns a
# sound card, and the fake that headless specs use in its place. If the fake
# drifts, `rake spec` stays green while the game plays nothing, which is the one
# failure the two-suite split cannot catch by itself.
#
# So both are run against this group: the fake from `spec/`, the real one from
# `spec_core/`. A method added to the real device is not done until it appears
# here and in the fake too.
#
# ## What the host must provide
#
#   with_audio { |audio, sound_path| ... }
#
# Yields a device, plus a path it will load. The fake accepts any path and never
# reads it; the real one is handed a fixture that exists. Loading is where the
# two genuinely differ, so the *path* is the host's business and everything
# after it is this group's.
#
# ## What this group does and does not check
#
# It checks the shape of the interface and the behaviour a caller can observe
# without listening: that the methods exist, that volumes clamp the same way,
# that a song reports the state it was put into. It cannot check that a sound
# comes out — the fake makes none. That is `test/test_audio.c`'s job, which
# opens a device with no device behind it and reads the mixed samples back, the
# audio equivalent of reading the framebuffer.
#
# It also says nothing about a sound *finishing*. Playback runs against a clock
# either way, so "is it still playing a moment later" is a timing question with
# no stable answer. Only the transitions a caller controls are stated here.
RSpec.shared_examples 'an audio server' do
  describe 'the device' do
    it 'names the sound system it opened' do
      with_audio do |audio, _path|
        expect(audio.backend).to be_a(String).and(satisfy { |name| !name.empty? })
      end
    end

    it 'starts at full volume' do
      with_audio { |audio, _path| expect(audio.volume).to eq(1.0) }
    end

    it 'round-trips a volume' do
      # A power of two, so the value survives the 32-bit float the real mixer
      # keeps it in. 0.8 would not, and an implementation is free to store it
      # that way.
      with_audio do |audio, _path|
        audio.volume = 0.25

        expect(audio.volume).to eq(0.25)
      end
    end

    it 'clamps a negative volume to silence' do
      # Not an error. A fader driven by a slider or an easing curve undershoots
      # constantly, and silence is the meaningful answer — below zero the
      # samples come out phase-inverted, which is louder rather than quieter.
      with_audio do |audio, _path|
        audio.volume = -2.0

        expect(audio.volume).to eq(0.0)
      end
    end

    it 'allows a volume above one' do
      # Amplification, deliberately permitted: a quiet asset is a real problem
      # and this is the fix. Avoiding clipping is the caller's job.
      with_audio do |audio, _path|
        audio.volume = 2.0

        expect(audio.volume).to eq(2.0)
      end
    end
  end

  # As with the renderer contract: each of these was a real difference between
  # FakeAudio and the live device, and the contract is what stops them drifting
  # apart again.
  describe 'arguments it refuses' do
    it 'refuses a volume that is not a number' do
      # `audio.volume = settings[:volume]` with a missing key.
      with_audio { |audio, _path| expect { audio.volume = nil }.to raise_error(TypeError) }
    end

    it 'refuses a nil path' do
      with_audio { |audio, _path| expect { audio.sample(nil) }.to raise_error(TypeError) }
      with_audio { |audio, _path| expect { audio.song(nil) }.to raise_error(TypeError) }
    end

    it 'refuses a volume that is not a number on a sound' do
      with_audio do |audio, path|
        expect { audio.sample(path).volume = nil }.to raise_error(TypeError)
      end
    end
  end

  describe 'samples' do
    it 'loads one from the device' do
      with_audio { |audio, path| expect(audio.sample(path)).to respond_to(:play) }
    end

    it 'plays' do
      with_audio { |audio, path| expect { audio.sample(path).play }.not_to raise_error }
    end

    it 'returns itself from play, so a call can be chained' do
      with_audio do |audio, path|
        sample = audio.sample(path)

        expect(sample.play).to equal(sample)
      end
    end

    it 'can be played again while it is still sounding' do
      # The defining property of a sample, and the reason it is not a song:
      # each play is another voice layered over the ones already out, so a fast
      # run of footsteps sounds like footsteps rather than one stuttering step.
      with_audio do |audio, path|
        sample = audio.sample(path)

        expect { 5.times { sample.play } }.not_to raise_error
      end
    end

    it 'round-trips a volume' do
      with_audio do |audio, path|
        sample = audio.sample(path)
        sample.volume = 0.5

        expect(sample.volume).to eq(0.5)
      end
    end

    it 'clamps a negative volume to silence' do
      with_audio do |audio, path|
        sample = audio.sample(path)
        sample.volume = -1.0

        expect(sample.volume).to eq(0.0)
      end
    end
  end

  describe 'songs' do
    it 'loads one from the device' do
      with_audio { |audio, path| expect(audio.song(path)).to respond_to(:play) }
    end

    it 'is not playing before it is played' do
      with_audio { |audio, path| expect(audio.song(path)).not_to be_playing }
    end

    it 'is playing after it is played' do
      with_audio do |audio, path|
        song = audio.song(path)
        # Looping, so the assertion cannot lose a race against a short fixture
        # reaching its own end.
        song.play(looping: true)

        expect(song).to be_playing
      end
    end

    it 'is not playing after it is stopped' do
      with_audio do |audio, path|
        song = audio.song(path)
        song.play(looping: true)
        song.stop

        expect(song).not_to be_playing
      end
    end

    it 'does not loop unless asked' do
      with_audio do |audio, path|
        song = audio.song(path)
        song.play

        expect(song).not_to be_looping
      end
    end

    it 'loops when asked' do
      with_audio do |audio, path|
        song = audio.song(path)
        song.play(looping: true)

        expect(song).to be_looping
      end
    end

    it 'ignores a stop it was not playing' do
      with_audio { |audio, path| expect { audio.song(path).stop }.not_to raise_error }
    end

    it 'returns itself from play and stop' do
      with_audio do |audio, path|
        song = audio.song(path)

        expect(song.play).to equal(song)
        expect(song.stop).to equal(song)
      end
    end

    it 'round-trips a volume' do
      with_audio do |audio, path|
        song = audio.song(path)
        song.volume = 0.75

        expect(song.volume).to eq(0.75)
      end
    end

    it 'clamps a negative volume to silence' do
      with_audio do |audio, path|
        song = audio.song(path)
        song.volume = -0.5

        expect(song.volume).to eq(0.0)
      end
    end
  end
end
