# frozen_string_literal: true

RSpec.describe RGame::Engine::AudioOut do
  let(:audio) { FakeAudio.new }
  let(:root) { RGame::Engine::Node2D.new }
  let(:out) { root.add_component(described_class.new(audio)) }
  let(:songs) { %i[town garden battle].to_h { [it, audio.song("#{it}.ogg")] } }

  def town = songs[:town]
  def garden = songs[:garden]
  def battle = songs[:battle]

  before do
    songs.each { |id, song| audio.register_music(id, song) }
    out
    root.enter_tree
    audio.clear
  end

  def tick(seconds) = root.update(seconds)
  def plays = audio.calls_to(:song_play).map(&:path)
  def playing = songs.select { |_, song| song.playing? }.keys

  # Rule 1.
  describe 'the winner' do
    it 'is the claim with the highest priority' do
      out.claim_music(:room, :town, priority: 1)
      out.claim_music(:fight, :battle, priority: 10)
      out.claim_music(:forest, :garden, priority: 2)

      expect(out.claimed_music).to eq(:battle)
      expect(playing).to eq(%i[battle])
    end

    it 'is the latest claim, in a tie' do
      out.claim_music(:room, :town, priority: 1)
      out.claim_music(:forest, :garden, priority: 1)

      expect(out.claimed_music).to eq(:garden)
    end

    it 'is nil while nothing claims the music' do
      expect(out.claimed_music).to be_nil
    end
  end

  # Rule 2.
  describe 'a change of winner' do
    it 'crossfades over the fade: of the call that changed it' do
      out.claim_music(:room, :town)
      out.claim_music(:fight, :battle, priority: 10, fade: 1.0)
      tick(0.25)

      expect(town.volume).to be_within(1e-9).of(0.75)
      expect(battle.volume).to be_within(1e-9).of(0.25)
      tick(0.75)
      expect(playing).to eq(%i[battle])
    end

    it 'crossfades back over the release\'s fade:' do
      out.claim_music(:room, :town)
      out.claim_music(:fight, :battle, priority: 10)
      out.release_music(:fight, fade: 0.5)
      tick(0.25)

      expect(town.volume).to be_within(1e-9).of(0.5)
      expect(battle.volume).to be_within(1e-9).of(0.5)
      expect(out.claimed_music).to eq(:town)
    end

    it 'changes the song once, for several keys released in one call' do
      out.claim_music(:room, :town, priority: 1)
      out.claim_music(:forest, :garden, priority: 2)
      out.claim_music(:fight, :battle, priority: 10)
      out.release_music(:fight, :forest)

      expect(plays).to eq(%w[town.ogg garden.ogg battle.ogg town.ogg])
      expect(playing).to eq(%i[town])
    end
  end

  describe 'a claim that leaves the winner as it was' do
    it 'starts nothing, for a claim of lower priority' do
      out.claim_music(:fight, :battle, priority: 10)
      out.claim_music(:room, :town, priority: 1, fade: 1.0)

      expect(plays).to eq(%w[battle.ogg])
      expect(battle.volume).to eq(1.0)
    end

    it 'starts nothing, for a second claim of the song already playing' do
      out.claim_music(:room, :town, priority: 1)
      out.claim_music(:square, :town, priority: 5, fade: 1.0)
      out.release_music(:room, fade: 1.0)

      expect(plays).to eq(%w[town.ogg])
      expect(audio.calls_to(:song_volume)).to be_empty
    end

    it 'starts nothing, for a release of a claim that was not winning' do
      out.claim_music(:fight, :battle, priority: 10)
      out.claim_music(:room, :town, priority: 1)
      out.release_music(:room, fade: 1.0)

      expect(plays).to eq(%w[battle.ogg])
    end

    it 'changes nothing, for a release of a key that holds no claim' do
      out.claim_music(:room, :town)
      out.release_music(:fight)

      expect(out.claimed_music).to eq(:town)
    end
  end

  # Rule 3.
  describe 'claiming a key again' do
    it 'replaces its song' do
      out.claim_music(:room, :town)
      out.claim_music(:room, :garden)

      expect(playing).to eq(%i[garden])
    end

    it 'replaces its priority' do
      out.claim_music(:fight, :battle, priority: 10)
      out.claim_music(:room, :town, priority: 1)
      out.claim_music(:room, :town, priority: 20)

      expect(out.claimed_music).to eq(:town)
    end

    it 'makes it the latest, for a tie' do
      out.claim_music(:room, :town, priority: 1)
      out.claim_music(:forest, :garden, priority: 1)
      out.claim_music(:room, :town, priority: 1)

      expect(out.claimed_music).to eq(:town)
    end
  end

  # Rule 4.
  it 'fades to silence and stops as the last claim is released' do
    out.claim_music(:room, :town)
    out.release_music(:room, fade: 1.0)
    tick(0.5)

    expect(town.volume).to be_within(1e-9).of(0.5)
    tick(0.5)
    expect(playing).to be_empty
    expect(out.claimed_music).to be_nil
  end

  it 'fades in the first claim over its fade:' do
    out.claim_music(:room, :town, fade: 1.0)
    tick(0.25)

    expect(town.volume).to be_within(1e-9).of(0.25)
  end

  # Rule 5.
  describe 'the direct calls, while a claim holds' do
    before { out.claim_music(:room, :town).claim_music(:fight, :battle, priority: 10) }

    it 'refuses play_music, naming the keys' do
      expect { out.play_music(:garden) }.to raise_error(RuntimeError, /play_music .*claimed by :room, :fight/)
    end

    it 'refuses crossfade' do
      expect { out.crossfade(:garden, over: 1.0) }.to raise_error(RuntimeError, /crossfade .*claimed/)
    end

    it 'refuses stop_music' do
      expect { out.stop_music }.to raise_error(RuntimeError, /stop_music .*claimed/)
    end

    it 'leaves the music as the claims chose it, after a refusal' do
      begin
        out.stop_music
      rescue RuntimeError
        nil
      end

      expect(playing).to eq(%i[battle])
    end

    it 'still pauses and resumes' do
      out.pause_music
      paused = playing
      out.resume_music

      expect([paused, playing]).to eq([[], %i[battle]])
    end

    it 'allows them again once every claim is released' do
      out.release_music(:room).release_music(:fight)
      out.play_music(:garden)

      expect(playing).to eq(%i[garden])
    end
  end

  it 'takes over from a song played directly' do
    out.play_music(:town)
    out.claim_music(:fight, :battle, fade: 1.0)
    tick(0.5)

    expect([town.volume, battle.volume]).to eq([0.5, 0.5])
  end

  describe 'a claim it refuses' do
    it 'refuses no song' do
      expect { out.claim_music(:room, nil) }.to raise_error(ArgumentError, /claim_music\(:room\) needs a song/)
    end

    it 'refuses a priority that is not a number' do
      expect { out.claim_music(:room, :town, priority: :high) }.to raise_error(TypeError, /priority is a number/)
    end

    it 'refuses a fade: that is not 0 or more seconds' do
      expect { out.claim_music(:room, :town, fade: -1) }.to raise_error(ArgumentError, /fade: must be 0 or more/)
      expect { out.release_music(:room, fade: -1) }.to raise_error(ArgumentError, /fade: must be 0 or more/)
    end
  end
end
