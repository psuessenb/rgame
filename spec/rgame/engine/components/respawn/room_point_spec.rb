# frozen_string_literal: true

# A RoomPoint on its own, and held by a Respawn in a world whose Scene::Rooms runs
# two MappedRooms. Room :a is all ground, with its gate at (24, 24). Room :b has
# gap cells at x 16 to 48, y 16 to 32, its door at (56, 24) on ground, and its pit
# at (24, 24) over a gap. A move fades for a quarter of a second each way.
RSpec.describe RGame::Engine::Components::Respawn::RoomPoint do
  it_behaves_like 'a respawn point' do
    def point_at(place) = described_class.new(room: :yard, location: place)
  end

  describe '.new' do
    it 'refuses a room that is not a Symbol, as Rooms#define does' do
      expect { described_class.new(room: 'a', location: 'gate') }.to raise_error(TypeError, /not "a"/)
    end
  end

  describe '#place' do
    it "raises when the room's _arrive leaves the node outside the room, as a move does" do
      stray = Class.new(RGame::Engine::Scene::Room) do
        def _arrive(node, _location) = parent.add_node(node)
      end
      room = stray.new.tap do |made|
        made.name = :c
        made.scene = made
      end
      RGame::Engine::Node2D.new.add_node(room)
      node = room.add_node(RGame::Engine::Node2D.new)
      room.root.enter_tree

      expect { described_class.new(room: :c, location: 'x').place(node) }
        .to raise_error(RuntimeError, /_arrive left RGame::Engine::Node2D outside the room/)
    end
  end

  describe 'held by a Respawn' do
    let(:players) { RGame::Engine::Players.new([RGame::Engine::Player.new(id: 0, device: RGame::Util::Controls::KEYBOARD)]) }
    let(:rooms) do
      top = RGame::Engine::Node2D.new.tap { it.add_component(players) }
      host = top.add_node(RGame::Engine::Node2D.new).tap { it.scene = it }
      host.add_component(RGame::Engine::Scene::Rooms.new).tap do |made|
        made.define(:a) { MappedRoom.new(['....', '....', '....'], objects: [['gate', 24, 24]]) }
        made.define(:b) { MappedRoom.new(['....', '.~~.', '....'], objects: [['door', 56, 24], ['pit', 24, 24]]) }
        made.transition = RGame::Engine::Scene::Fade.new(cover: 0.25, reveal: 0.25)
        top.enter_tree
      end
    end
    let(:respawn) { RGame::Engine::Components::Respawn.new }
    let(:hero) { RGame::Engine::Node2D.new(input_owner: players.primary).tap { it.add_component(respawn) } }
    let(:seen) { [] }

    def room_of(node) = RGame::Engine::Scene::Room.of(node)&.name

    def tick
      top = rooms.node.root
      players.poll(FakeInputBackend.new, 1.0 / 60)
      top.control(players)
      top.update(1.0 / 60)
      top.sweep_freed
    end

    # Ticks until the block answers true.
    def tick_until(limit = 120)
      (1..limit).find do
        tick
        yield
      end || raise("still waiting after #{limit} ticks")
    end

    def settled? = !rooms.pending? && !rooms.transitioning?

    def go(to:, location:)
      rooms.move(hero, to:, location:)
      tick_until { settled? }
    end

    before do
      go(to: :a, location: 'gate')
      respawn.on_respawned { seen << [room_of(hero), hero.world_x, hero.world_y] }
    end

    it 'is the point a Respawn with none takes from its first move' do
      expect(respawn.point).to eq(described_class.new(room: :a, location: 'gate'))
    end

    it "brings the node back in its own room at once, through the room's _arrive, under no cover" do
      hero.x = 50.0
      respawn.respawn

      expect([seen, rooms.pending?, hero.suspended?, players.primary.input_suspended?])
        .to eq([[[:a, 24.0, 24.0]], false, false, false])
    end

    it "moves the node back to its room under the rooms' transition, and says so once, as it attaches there" do
      go(to: :b, location: 'door')
      respawn.respawn
      asked = [rooms.pending?, rooms.transitioning?, hero.suspended?, seen.dup]
      tick_until { !rooms.pending? }
      landed = seen.dup
      tick_until { settled? }

      expect([asked, landed, seen, hero.suspended?])
        .to eq([[true, true, true, []], [[:a, 24.0, 24.0]], [[:a, 24.0, 24.0]], false])
    end

    it 'ends with no on_respawned when another move replaces its own, nor at a later arrival in its room' do
      go(to: :b, location: 'door')
      respawn.respawn
      rooms.move(hero, to: :b, location: 'door')
      tick_until { settled? }
      go(to: :a, location: 'gate')

      expect([room_of(hero), seen]).to eq([:a, []])
    end

    it 'checks nothing while the node stands in another room, and checks the point as it attaches there' do
      respawn.set_point(described_class.new(room: :b, location: 'pit'))
      rooms.move(hero, to: :b, location: 'door')

      expect { tick_until { !rooms.pending? } }
        .to raise_error(ArgumentError, /Node2D's respawn point "pit" in room :b is over a gap/)
    end

    it 'refuses set_point over a gap in the room the node stands in, and keeps the point it had' do
      go(to: :b, location: 'door')

      expect { respawn.set_point(described_class.new(room: :b, location: 'pit')) }
        .to raise_error(ArgumentError, /"pit" in room :b is over a gap/)
      expect(respawn.point).to eq(described_class.new(room: :a, location: 'gate'))
    end

    it 'raises KeyError at set_point for a location the room does not name' do
      expect { respawn.set_point(described_class.new(room: :a, location: 'well')) }
        .to raise_error(KeyError, /no location named 'well'/)
    end
  end
end
