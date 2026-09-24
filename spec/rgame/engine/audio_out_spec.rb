# frozen_string_literal: true

RSpec.describe RGame::Engine::AudioOut do
  # The same FakeAudio the audio contract runs against, so a call the real
  # device would refuse fails here too.
  let(:audio) { FakeAudio.new }
  let(:root) { RGame::Engine::Node2D.new }
  let(:node) { root.add_node(RGame::Engine::Node2D.new) }
  let(:out) { node.system!(described_class) }
  let(:songs) { %i[theme battle boss].to_h { [it, audio.song("#{it}.ogg")] } }

  def theme = songs[:theme]
  def battle = songs[:battle]
  def boss = songs[:boss]

  before do
    audio.register_sound(:shoot, audio.sample('shoot.ogg'))
    songs.each { |id, song| audio.register_music(id, song) }
    audio.clear
    root.add_component(described_class.new(audio))
    root.enter_tree
  end

  def tick(seconds) = root.update(seconds)
  def ticks(count) = count.times { root.update(1.0 / 60) }
  def volume_calls(path) = audio.calls_to(:song_volume).count { it.path == path }

  it 'forwards each call to the audio server' do
    out.play_music(:theme)
    out.play_sound(:shoot)
    out.stop_music

    expect(audio.calls.map(&:name)).to eq(%i[song_play sample_play song_stop])
  end

  it 'plays the sound the id names' do
    out.play_sound(:shoot)

    expect(audio.played?('shoot.ogg')).to be(true)
  end

  it 'leaves looping to the server' do
    out.play_music(:theme)

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

  describe 'a fade in' do
    it 'starts the song at silence and reaches full volume after the fade' do
      out.play_music(:theme, fade: 1.0)
      at_start = [theme.volume, theme.playing?]
      tick(0.25)
      quarter = theme.volume
      tick(0.75)

      expect(at_start).to eq([0.0, true])
      expect(quarter).to be_within(1e-9).of(0.25)
      expect(theme.volume).to eq(1.0)
      expect(out).not_to be_fading
    end

    it 'steps the volume once a tick' do
      out.play_music(:theme, fade: 1.0)
      ticks(70)

      expect(volume_calls('theme.ogg')).to eq(1 + 60)
    end

    it 'sends only the call it sent before fades existed, when there is no fade' do
      out.play_music(:theme)
      ticks(10)

      expect(audio.calls.map(&:name)).to eq(%i[song_play])
    end

    it 'refuses a fade that is not 0 or more seconds' do
      expect { out.play_music(:theme, fade: -1) }.to raise_error(ArgumentError, /fade: must be 0 or more/)
      expect { out.play_music(:theme, fade: nil) }.to raise_error(ArgumentError, /fade: must be 0 or more/)
    end
  end

  describe 'a fade out' do
    it 'lowers the current song to silence and stops it on the tick it arrives' do
      out.play_music(:theme)
      out.stop_music(fade: 0.5)
      tick(0.25)
      halfway = [theme.volume, theme.playing?]
      tick(0.25)

      expect(halfway).to eq([0.5, true])
      expect(theme).not_to be_playing
      expect(out).not_to be_fading
    end

    it 'plays the song at full volume the next time' do
      out.play_music(:theme)
      out.stop_music(fade: 0.5)
      tick(0.5)
      out.play_music(:theme)

      expect([theme.volume, theme.playing?]).to eq([1.0, true])
    end

    it 'sends only the call it sent before fades existed, when there is no fade' do
      out.play_music(:theme)
      audio.clear
      out.stop_music

      expect(audio.calls.map(&:name)).to eq(%i[song_stop])
    end

    it 'stops at once, and at full volume, a song whose fade a plain stop cuts short' do
      out.play_music(:theme)
      out.stop_music(fade: 1.0)
      tick(0.5)
      out.stop_music

      expect([theme.playing?, theme.volume]).to eq([false, 1.0])
      expect(out).not_to be_fading
    end
  end

  describe 'a crossfade' do
    it 'lowers the current song while it raises the new one, and stops the old one when it is silent' do
      out.play_music(:theme)
      out.crossfade(:battle, over: 1.0)
      tick(0.5)
      halfway = [theme.volume, battle.volume, theme.playing?]
      tick(0.5)

      expect(halfway).to eq([0.5, 0.5, true])
      expect([theme.playing?, battle.playing?]).to eq([false, true])
      expect([theme.volume, battle.volume]).to eq([1.0, 1.0])
    end

    it 'is a fade in with no current song' do
      out.crossfade(:battle, over: 1.0)
      at_start = battle.volume
      tick(0.5)

      expect([at_start, battle.volume]).to eq([0.0, 0.5])
    end

    it 'stops the song on its way out when a second one begins, and brings the one coming in down' do
      out.play_music(:theme)
      out.crossfade(:battle, over: 1.0)
      tick(0.5)
      out.crossfade(:boss, over: 1.0)
      theme_stopped = !theme.playing?
      tick(0.5)

      expect(theme_stopped).to be(true)
      expect(theme.volume).to eq(1.0)
      expect(battle.volume).to be_within(1e-9).of(0.25)
      expect(boss.volume).to be_within(1e-9).of(0.5)
    end

    it 'refuses an over: that is not 0 or more seconds' do
      expect { out.crossfade(:battle, over: -0.5) }.to raise_error(ArgumentError, /over: must be 0 or more/)
    end
  end

  describe 'asking for the song on its way out' do
    it 'brings it back up from where it is, without starting it again' do
      out.play_music(:theme)
      out.stop_music(fade: 1.0)
      tick(0.5)
      out.play_music(:theme, fade: 1.0)
      tick(0.5)

      expect(theme.volume).to be_within(1e-9).of(0.75)
      expect(audio.calls_to(:song_play).size).to eq(1)
      expect(theme).to be_playing
    end

    it 'turns a crossfade back, each song from where it is' do
      out.play_music(:theme)
      out.crossfade(:battle, over: 1.0)
      tick(0.25)
      out.crossfade(:theme, over: 1.0)
      tick(0.5)

      expect(theme.volume).to be_within(1e-9).of(0.875)
      expect(battle.volume).to be_within(1e-9).of(0.125)
      expect(audio.calls_to(:song_play).size).to eq(2)
      expect([theme.playing?, battle.playing?]).to eq([true, true])
    end
  end

  describe 'pausing' do
    it 'holds the song and its fade where they are, and carries both on' do
      out.play_music(:theme, fade: 1.0)
      tick(0.5)
      out.pause_music
      paused = theme.playing?
      tick(2.0)
      held = theme.volume
      out.resume_music
      tick(0.25)

      expect([paused, held]).to eq([false, 0.5])
      expect(theme).to be_playing
      expect(theme.volume).to be_within(1e-9).of(0.75)
    end

    it 'holds a fade out where it is, and carries it on' do
      out.play_music(:theme)
      out.stop_music(fade: 1.0)
      tick(0.5)
      out.pause_music
      paused = theme.playing?
      tick(2.0)
      held = theme.volume
      out.resume_music
      tick(0.25)

      expect([paused, held]).to eq([false, 0.5])
      expect(theme.volume).to be_within(1e-9).of(0.25)
      tick(0.25)
      expect(theme).not_to be_playing
    end

    it 'stops the song on its way out of a crossfade' do
      out.play_music(:theme)
      out.crossfade(:battle, over: 1.0)
      tick(0.5)
      out.pause_music

      expect([theme.playing?, theme.volume]).to eq([false, 1.0])
      out.resume_music
      expect([theme.playing?, battle.playing?]).to eq([false, true])
    end
  end

  it 'fades out after the node that asked for it has left the tree' do
    scene = root.add_node(RGame::Engine::Node2D.new)
    scene.system!(described_class).play_music(:theme)
    scene.system!(described_class).stop_music(fade: 0.5)
    root.remove_node(scene)
    tick(0.5)

    expect(theme).not_to be_playing
  end

  it 'reads and sets a category volume on the audio server' do
    out.set_category_volume(:music, 0.5)

    expect(out.category_volume(:music)).to eq(0.5)
    expect { out.category_volume(:voice) }.to raise_error(KeyError)
  end
end
