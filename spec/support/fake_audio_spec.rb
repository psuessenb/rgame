# frozen_string_literal: true

RSpec.describe FakeAudio do
  # Half of why this file exists: the fake is run against the same contract as
  # the real device, so it cannot quietly fall behind it. The other half is the
  # recording itself, which engine specs assert against.
  subject(:audio) { described_class.new }

  # The contract's hook. The fake needs nothing set up and never opens the path,
  # so this just yields; the real device's version opens one and hands over a
  # fixture that exists.
  def with_audio = yield(audio, 'assets/hit.ogg')

  it_behaves_like 'an audio server'

  describe 'recording' do
    it 'keeps each play with the sound it happened to' do
      audio.sample('hit.ogg').play
      audio.song('theme.ogg').play(looping: true)

      expect(audio.calls.map { |call| [call.name, call.path] })
        .to eq([[:sample, 'hit.ogg'], [:sample_play, 'hit.ogg'],
                [:song, 'theme.ogg'], [:song_play, 'theme.ogg']])
    end

    it 'keeps the arguments a play was made with' do
      audio.song('theme.ogg').play(looping: true)

      expect(audio.calls_to(:song_play).first.args).to eq([true])
    end

    it 'answers whether a particular sound was played' do
      audio.sample('hit.ogg').play

      expect(audio.played?('hit.ogg')).to be(true)
      expect(audio.played?('miss.ogg')).to be(false)
    end

    it 'answers whether anything was played at all' do
      expect(audio.played?).to be(false)

      audio.song('theme.ogg').play
      expect(audio.played?).to be(true)
    end

    it 'does not count loading as playing' do
      # Loading a sound at startup is not the same event as triggering it, and a
      # spec that could not tell them apart would pass on a scene that loads
      # everything and plays nothing.
      audio.sample('hit.ogg')

      expect(audio.played?).to be(false)
    end

    it 'records a volume change on the device' do
      audio.volume = 0.5

      expect(audio.calls_to(:volume).first.args).to eq([0.5])
    end

    it 'records a volume change on a sound, against that sound' do
      audio.sample('hit.ogg').volume = 0.5

      expect(audio.calls_to(:sample_volume).map { |call| [call.path, call.args] })
        .to eq([['hit.ogg', [0.5]]])
    end

    it 'records calls in the order they were made' do
      song = audio.song('theme.ogg')
      song.play
      audio.sample('hit.ogg').play
      song.stop

      expect(audio.calls.map(&:name)).to eq(%i[song song_play sample sample_play song_stop])
    end

    it 'forgets everything on #clear, so one spec can drive several frames' do
      audio.sample('hit.ogg').play

      expect(audio.clear.calls).to be_empty
    end
  end

  describe 'a song it made' do
    it 'knows its own path, so a spec can tell two apart' do
      expect(audio.song('theme.ogg').path).to eq('theme.ogg')
    end

    it 'goes back to not looping when it is replayed without the keyword' do
      song = audio.song('theme.ogg')
      song.play(looping: true)
      song.play

      expect(song).not_to be_looping
    end
  end
end
