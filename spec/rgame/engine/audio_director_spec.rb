# frozen_string_literal: true

RSpec.describe RGame::Engine::AudioDirector do
  subject(:director) { described_class.new(audio) }

  # A spy standing in for the audio backend. Platform::GosuAudio can't load headless
  # (it requires Gosu), so this stays a string reference: it verifies method signatures
  # anywhere Platform is loaded and degrades to a plain double here. The disable also
  # guards against autocorrect turning it into a bare constant, which would crash headless.
  let(:audio) { instance_spy('Platform::GosuAudio') } # rubocop:disable RSpec/VerifiedDoubleReference

  describe 'subscribe' do
    it 'registers as the handler for the audio events' do
      director.subscribe

      RGame::Engine::AudioBus.on_play_music.emit(:heartbeat)
      RGame::Engine::AudioBus.on_play_sound.emit(:shoot)
      RGame::Engine::AudioBus.on_stop_music.emit

      expect(audio).to have_received(:play_music).with(:heartbeat).ordered
      expect(audio).to have_received(:play_sound).with(:shoot).ordered
      expect(audio).to have_received(:stop_music).ordered
    end

    it 'returns self so it can be built and subscribed in one expression' do
      expect(director.subscribe).to be(director)
    end
  end
end
