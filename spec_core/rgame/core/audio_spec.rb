# frozen_string_literal: true

# Audio, Sample and Song share one spec file, the way they share audio_ext.c:
# every example needs a device, and the two sound classes are only meaningful
# against one.
#
# Most of the *behaviour* is not here. It is in the 'an audio server' contract
# in spec/, which FakeAudio is run against too — see CLAUDE.md, "Fakes must be
# checked against the same contract as the real thing". What is left here is
# what only the real one has: loading files, the errors a bad one raises, and
# not leaking.
#
# What comes *out* of the mixer is not here either. test/test_audio.c opens a
# device with no device behind it and reads the mixed samples back, which is the
# audio equivalent of reading the framebuffer, and there is no way to reach it
# from Ruby by design: a game wants the constructor that opens a real device.
RSpec.describe RGame::Core::Audio do
  # A device per example. Named by its full constant rather than
  # `described_class` because the nested groups below describe Sample and Song,
  # and a `let` body is evaluated where it is *used*, not where it is written.
  #
  # Opening one costs single-digit milliseconds, so there is nothing to save by
  # sharing it and a shared device would let one example's volume change reach
  # another's.
  # rubocop:disable RSpec/DescribedClass -- described_class is Sample or Song in the nested groups
  let(:audio) { RGame::Core::Audio.new }
  # rubocop:enable RSpec/DescribedClass

  # The contract's hook. The real device is opened here and the path is a
  # fixture that exists, which is the whole of what it needs that the fake does
  # not.
  def with_audio = yield(audio, AudioFixture::OGG)

  it_behaves_like 'an audio server'

  # Sounds alive right now, after collecting whatever is unreachable.
  #
  # The settle is not optional, for the same reason Image's is not: the counter
  # is process-wide, so sounds dropped by earlier examples still count until a
  # collection runs, and that happens at a moment nothing controls.
  def live_sounds
    3.times { GC.start(full_mark: true, immediate_sweep: true) }
    described_class.debug_live_sounds
  end

  describe '#backend' do
    it 'names a sound system that exists' do
      # Which one depends on the machine — PulseAudio or ALSA on Linux,
      # "Core Audio" on macOS, WASAPI on Windows, Null on a CI runner with no
      # sound card, and a game runs either way. The contract only says it is a
      # non-empty String; this says it is one of ours.
      #
      # The spellings are miniaudio's, not ours: they come from `gBackendInfo`
      # in ext/rgame_core/vendor/miniaudio.h, which is why macOS is "Core
      # Audio" with a space rather than the "CoreAudio" of the MA_ENABLE_ macro.
      expect(audio.backend).to match(/\A(PulseAudio|ALSA|Core Audio|WASAPI|Null)\z/)
    end
  end

  describe '#inspect' do
    it 'shows the backend' do
      expect(audio.inspect).to eq("#<RGame::Core::Audio #{audio.backend}>")
    end
  end

  describe '.debug_live_sounds' do
    it 'returns to its baseline once sounds are collected' do
      baseline = live_sounds

      10.times do
        audio.sample(AudioFixture::OGG)
        audio.song(AudioFixture::OGG)
      end

      expect(live_sounds).to eq(baseline)
    end
  end

  describe RGame::Core::Sample do
    describe '.new' do
      it 'is what Audio#sample builds' do
        # Both forms exist: the constructor because that is how a C-backed class
        # is made, and Audio#sample because a stand-in device can offer it and
        # `Sample.new` cannot.
        expect(described_class.new(audio, AudioFixture::OGG)).to be_a(described_class)
      end

      it 'loads Vorbis' do
        expect(audio.sample(AudioFixture::OGG)).to be_a(described_class)
      end

      it 'loads WAV' do
        # A different decoder inside miniaudio than Vorbis takes, so this is not
        # the same path twice — and Vorbis is the one this project wired in by
        # hand (ext/rgame_core/audio/vorbis_decoder.c).
        expect(audio.sample(AudioFixture.write_wav)).to be_a(described_class)
      end

      it 'raises LoadError naming a file it cannot read' do
        expect { audio.sample('/no/such/hit.ogg') }
          .to raise_error(described_class::LoadError, %r{/no/such/hit\.ogg})
      end

      it 'raises LoadError for a file that is not a sound' do
        # Named .ogg but full of text: the engine must decide by content.
        expect { audio.sample(AudioFixture.write_garbage) }
          .to raise_error(described_class::LoadError)
      end

      it 'refuses anything that is not an Audio' do
        expect { described_class.new(Object.new, AudioFixture::OGG) }.to raise_error(TypeError)
      end
    end

    it 'keeps its device alive' do
      # The sound is a voice inside the device's mixer. If the collector took
      # the device first, playing would be a use-after-free — at a moment that
      # depends on when a collection happened to run, which is the worst kind of
      # crash to be handed. Holding no other reference to the device is the
      # whole point of the example: with audio_ext.c's mark function removed,
      # this segfaults.
      sample = RGame::Core::Audio.new.sample(AudioFixture::OGG)
      3.times { GC.start(full_mark: true, immediate_sweep: true) }

      expect { sample.play }.not_to raise_error
    end
  end

  describe RGame::Core::Song do
    describe '.new' do
      it 'is what Audio#song builds' do
        expect(described_class.new(audio, AudioFixture::OGG)).to be_a(described_class)
      end

      it 'raises LoadError naming a file it cannot read' do
        expect { audio.song('/no/such/theme.ogg') }
          .to raise_error(described_class::LoadError, %r{/no/such/theme\.ogg})
      end

      it 'raises LoadError for a file that is not a sound' do
        expect { audio.song(AudioFixture.write_garbage) }
          .to raise_error(described_class::LoadError)
      end

      it 'refuses anything that is not an Audio' do
        expect { described_class.new(Object.new, AudioFixture::OGG) }.to raise_error(TypeError)
      end
    end

    it 'keeps its device alive' do
      orphan = RGame::Core::Audio.new.song(AudioFixture::OGG)
      3.times { GC.start(full_mark: true, immediate_sweep: true) }

      expect { orphan.play }.not_to raise_error
    end
  end
end
