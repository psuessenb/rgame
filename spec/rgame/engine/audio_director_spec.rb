# frozen_string_literal: true

RSpec.describe RGame::Engine::AudioDirector do
  subject(:director) { described_class.new(audio) }

  # The same `FakeAudio` the audio contract is run against, rather than a double
  # of the director's own imagining. That matters here more than usual: the
  # director's entire job is to call an audio server by method name, so a
  # stand-in that accepted calls the real device would refuse would leave this
  # spec green and the game silent. See CLAUDE.md, "Fakes must be checked
  # against the same contract as the real thing".
  let(:audio) { FakeAudio.new }

  before do
    audio.register_sound(:shoot, audio.sample('shoot.ogg'))
    audio.register_music(:heartbeat, audio.song('heartbeat.ogg'))
    audio.clear # forget the loads; what these examples are about is playback
  end

  describe 'subscribe' do
    it 'turns each audio event into the matching call' do
      director.subscribe

      RGame::Engine::AudioBus.on_play_music.emit(:heartbeat)
      RGame::Engine::AudioBus.on_play_sound.emit(:shoot)
      RGame::Engine::AudioBus.on_stop_music.emit

      expect(audio.calls.map(&:name)).to eq(%i[song_play sample_play song_stop])
    end

    it 'names the sound the event carried' do
      director.subscribe
      RGame::Engine::AudioBus.on_play_sound.emit(:shoot)

      expect(audio.played?('shoot.ogg')).to be(true)
    end

    it 'loops music rather than playing it once' do
      # Gameplay says "play the theme", not "play the theme on repeat"; deciding
      # that music loops is the server's business, and this is where a scene
      # would find out if it stopped.
      director.subscribe
      RGame::Engine::AudioBus.on_play_music.emit(:heartbeat)

      expect(audio.calls_to(:song_play).first.args).to eq([true])
    end

    it 'returns self so it can be built and subscribed in one expression' do
      expect(director.subscribe).to be(director)
    end
  end
end
