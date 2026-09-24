# frozen_string_literal: true

# A tick is an eighth of a second, so a Fade of half a second covers in four
# ticks and reveals in four more, and a move's song crossfades over all eight.
# rubocop:disable RSpec/MultipleMemoizedHelpers -- two players, their heroes, the device and the tree every group shares
RSpec.describe RGame::Engine::Scene::Rooms do
  let(:fade) { RGame::Engine::Scene::Fade.new(cover: 0.5, reveal: 0.5) }
  let(:audio) { FakeAudio.new }
  let(:backend) { FakeInputBackend.new }
  let(:first) { RGame::Engine::Player.new(id: 0, device: RGame::Util::Controls::KEYBOARD) }
  let(:second) { RGame::Engine::Player.new(id: 1, device: RGame::Util::Controls.gamepad(0)) }
  let(:players) { RGame::Engine::Players.new([first, second]) }
  let(:out) { RGame::Engine::AudioOut.new(audio) }
  let(:root) do
    RGame::Engine::Node2D.new.tap do |root|
      root.add_component(players)
      root.add_component(RGame::Engine::Viewports.new(players, width: 320, height: 240))
      root.add_component(out)
    end
  end
  let(:world) { root.add_node(RGame::Engine::Node2D.new).tap { it.scene = it } }
  let(:rooms) { world.add_component(described_class.new) }
  let(:hero) { RGame::Engine::Node2D.new(input_owner: first) }
  let(:other_hero) { RGame::Engine::Node2D.new(input_owner: second) }
  let(:songs) { %i[town garden forest battle].to_h { [it, audio.song("#{it}.ogg")] } }

  def tick
    players.poll(backend, 0.125)
    root.control(players)
    root.update(0.125)
    root.sweep_freed
  end

  def playing = songs.select { |_, song| song.playing? }.keys
  def volumes = songs.filter_map { |id, song| [id, song.volume] if song.playing? }.to_h
  def plays = audio.calls_to(:song_play).map(&:path)

  before { songs.each { |id, song| audio.register_music(id, song) } }

  # Rule 6.
  describe 'a room\'s song' do
    before do
      rooms.define(:town, music: :town, priority: 1) { SpecRoom.new }
      rooms.define(:garden, music: :garden, priority: 2) { SpecRoom.new }
      rooms.define(:forest, music: :forest, priority: 3) { SpecRoom.new }
      rooms.define(:cellar) { SpecRoom.new }
      root.enter_tree
      rooms.move([hero, other_hero], to: :town, entrance: 'gate')
      tick
      audio.clear
      rooms.transition = fade
    end

    it 'plays while a player stands in the room' do
      expect(playing).to eq(%i[town])
    end

    it 'plays the room of the highest priority, of the rooms players stand in' do
      rooms.move(other_hero, to: :garden, entrance: 'well', transition: nil)
      tick

      expect(playing).to eq(%i[garden])
      expect(rooms.room_of(first).name).to eq(:town)
    end

    it 'is claimed as the move is asked for, and crossfades over the cover and the reveal' do
      rooms.move(other_hero, to: :garden, entrance: 'well')
      asked = out.claimed_music
      4.times { tick }
      halfway = volumes
      4.times { tick }

      expect(asked).to eq(:garden)
      expect(halfway).to eq(town: 0.5, garden: 0.5)
      expect(playing).to eq(%i[garden])
    end

    it 'comes back over the move\'s transition once the player of the higher room leaves it' do
      rooms.move(other_hero, to: :garden, entrance: 'well', transition: nil)
      tick
      rooms.move(other_hero, to: :town, entrance: 'gate')
      4.times { tick }
      halfway = volumes
      4.times { tick }

      expect(halfway).to eq(town: 0.5, garden: 0.5)
      expect(playing).to eq(%i[town])
      expect(out.claimed_music).to eq(:town)
    end

    it 'is claimed already as requested fires' do
      claimed = []
      rooms.on_requested { claimed << out.claimed_music }
      rooms.move(other_hero, to: :garden, entrance: 'well')

      expect(claimed).to eq(%i[garden])
    end

    it 'goes straight to the song every hero ends under, for a move of several' do
      rooms.move(hero, to: :forest, entrance: 'well', transition: nil)
      rooms.move(other_hero, to: :garden, entrance: 'well', transition: nil)
      tick
      audio.clear
      rooms.move([hero, other_hero], to: :town, entrance: 'gate', transition: nil)

      expect(plays).to eq(%w[town.ogg])
      expect(playing).to eq(%i[town])
    end

    it 'goes silent once every player stands in rooms that claim nothing' do
      rooms.move([hero, other_hero], to: :cellar, entrance: 'gate', transition: nil)
      tick

      expect(playing).to be_empty
      expect(out.claimed_music).to be_nil
    end

    it 'is not claimed for a room a hold keeps with nobody in it' do
      rooms.hold(:forest)
      tick

      expect(playing).to eq(%i[town])
    end

    it 'starts nothing again for a warp inside the room' do
      rooms.move(hero, to: :town, entrance: 'well')
      8.times { tick }

      expect(plays).to be_empty
      expect(playing).to eq(%i[town])
    end

    it 'yields to a claim a game makes over every room' do
      out.claim_music(:battle, :battle, priority: 10)
      rooms.move(other_hero, to: :forest, entrance: 'well', transition: nil)
      tick

      expect(playing).to eq(%i[battle])
    end

    it 'is claimed under a key no game can release' do
      out.release_music(:town)

      expect(out.claimed_music).to eq(:town)
      expect { out.stop_music }.to raise_error(RuntimeError, /claimed by the room :town/)
    end

    it 'stops as the rooms leave the tree' do
      root.remove_node(world)

      expect(playing).to be_empty
      expect(out.claimed_music).to be_nil
    end

    it 'refuses a priority that is not a number' do
      expect { rooms.define(:attic, music: :town, priority: 'high') { SpecRoom.new } }
        .to raise_error(TypeError, /priority is a number/)
    end
  end

  it 'fades a room\'s song in over the reveal alone, for a player in no room, whose cover is complete at once' do
    rooms.define(:garden, music: :garden, priority: 2) { SpecRoom.new }
    root.enter_tree
    rooms.move(hero, to: :garden, entrance: 'well', transition: fade)
    4.times { tick }

    expect(volumes).to eq(garden: 1.0)
  end

  # Rule 7.
  it 'lets a game play the primary player\'s room, claiming one key of its own from on_arrived' do
    rooms.define(:town) { SpecRoom.new }
    rooms.define(:garden) { SpecRoom.new }
    rooms.on_arrived do |_node, room|
      out.claim_music(:primary, room.name) if rooms.room_of(players.primary).equal?(room)
    end
    root.enter_tree
    rooms.move([hero, other_hero], to: :town, entrance: 'gate')
    tick
    rooms.move(other_hero, to: :garden, entrance: 'well')
    tick
    unmoved = playing
    rooms.move(hero, to: :garden, entrance: 'well')
    tick

    expect(unmoved).to eq(%i[town])
    expect(playing).to eq(%i[garden])
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
