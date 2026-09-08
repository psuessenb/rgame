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

  # AudioBus is a module, so its listeners outlive the example that added them.
  # Without this, every example here leaves a director on the global hub and the
  # next one's emits reach both.
  after { director.unsubscribe }

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

  # The half that makes an App collectable. AudioBus holds its listeners until
  # something takes them off, and a listener holds the director, which holds the
  # audio device, which holds the asset manager it resolves paths through, which
  # holds the App and its window. RGame::Game calls this when its loop ends;
  # nothing else has to.
  describe 'unsubscribe' do
    it 'stops turning events into calls' do
      director.subscribe
      director.unsubscribe

      RGame::Engine::AudioBus.on_play_sound.emit(:shoot)

      expect(audio.played?).to be(false)
    end

    it 'leaves another director on the same bus alone' do
      # Each one takes off *its own* listeners. Disconnecting by clearing the
      # signal would silence a second game sharing the process — which is
      # exactly the situation the whole method exists for.
      other_audio = FakeAudio.new
      other_audio.register_sound(:shoot, other_audio.sample('shoot.ogg'))
      other = described_class.new(other_audio).subscribe
      director.subscribe
      director.unsubscribe

      RGame::Engine::AudioBus.on_play_sound.emit(:shoot)

      expect(other_audio.played?('shoot.ogg')).to be(true)
      expect(audio.played?).to be(false)
      other.unsubscribe
    end

    it 'is safe on a director that was never subscribed' do
      expect { described_class.new(audio).unsubscribe }.not_to raise_error
    end

    it 'is safe to call twice' do
      director.subscribe

      expect { 2.times { director.unsubscribe } }.not_to raise_error
    end

    it 'returns self' do
      expect(director.subscribe.unsubscribe).to be(director)
    end
  end
end
