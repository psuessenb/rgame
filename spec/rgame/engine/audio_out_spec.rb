# frozen_string_literal: true

RSpec.describe RGame::Engine::AudioOut do
  # The same FakeAudio the audio contract runs against, so a call the real
  # device would refuse fails here too.
  let(:audio) { FakeAudio.new }
  let(:root) { RGame::Engine::Node2D.new }
  let(:node) { root.add_node(RGame::Engine::Node2D.new) }

  before do
    audio.register_sound(:shoot, audio.sample('shoot.ogg'))
    audio.register_music(:heartbeat, audio.song('heartbeat.ogg'))
    audio.clear
    root.add_component(described_class.new(audio))
  end

  it 'forwards each call to the audio server' do
    out = node.system!(described_class)
    out.play_music(:heartbeat)
    out.play_sound(:shoot)
    out.stop_music

    expect(audio.calls.map(&:name)).to eq(%i[song_play sample_play song_stop])
  end

  it 'plays the sound the id names' do
    node.system!(described_class).play_sound(:shoot)

    expect(audio.played?('shoot.ogg')).to be(true)
  end

  it 'leaves looping to the server' do
    node.system!(described_class).play_music(:heartbeat)

    expect(audio.calls_to(:song_play).first.args).to eq([true])
  end

  it 'is reached from a scene below the root' do
    scene = node.add_node(RGame::Engine::Node2D.new)
    scene.scene = scene
    scene.add_node(RGame::Engine::Node2D.new).system!(described_class).play_sound(:shoot)

    expect(audio.played?('shoot.ogg')).to be(true)
  end

  it 'raises naming AudioOut for a node outside the tree' do
    expect { RGame::Engine::Node2D.new.system!(described_class).play_sound(:shoot) }
      .to raise_error(KeyError, /no RGame::Engine::AudioOut system/)
  end
end
