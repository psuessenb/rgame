# frozen_string_literal: true

# Each tick runs as RGame::Game runs one: a poll, a control of the whole tree,
# an update and a sweep.
# rubocop:disable RSpec/MultipleMemoizedHelpers -- two players, their heroes, the tree and the log every group shares
RSpec.describe RGame::Engine::Scene::Rooms do
  let(:backend) { FakeInputBackend.new }
  let(:first) { RGame::Engine::Player.new(id: 0, device: RGame::Util::Controls::KEYBOARD) }
  let(:second) { RGame::Engine::Player.new(id: 1, device: RGame::Util::Controls.gamepad(0)) }
  let(:players) { RGame::Engine::Players.new([first, second]) }
  let(:root) { RGame::Engine::Node2D.new.tap { it.add_component(players) } }
  let(:world) { root.add_node(RGame::Engine::Node2D.new).tap { it.scene = it } }
  let(:rooms) { world.add_component(described_class.new) }
  let(:log) { [] }
  let(:hero) { RGame::Engine::Node2D.new(input_owner: first) }
  let(:other_hero) { RGame::Engine::Node2D.new(input_owner: second) }

  def dt = 1.0 / 60

  def tick(times = 1)
    times.times do
      players.poll(backend, dt)
      root.control(players)
      root.update(dt)
      root.sweep_freed
    end
  end

  def sweep = root.sweep_freed

  before do
    rooms.define(:town) { SpecRoom.new(log) }
    rooms.define(:garden) { SpecRoom.new(log) }
    root.enter_tree
  end

  # Rules 1 and 4.
  describe 'a move' do
    it 'lands in the next sweep, not when asked' do
      rooms.move(hero, to: :town, entrance: 'gate')
      asked = [rooms[:town], rooms.pending?]
      sweep
      expect(asked + [rooms[:town].class, rooms.pending?]).to eq([nil, true, SpecRoom, false])
    end

    it 'builds the room, and hands the node to its _arrive with the entrance' do
      rooms.move(hero, to: :town, entrance: 'gate')
      sweep
      town = rooms[:town]
      expect([town.arrivals, town.name, town.in_tree?, town.scene]).to eq([[[hero, 'gate']], :town, true, town])
    end

    it 'places the node where _arrive puts it' do
      rooms.move(hero, to: :town, entrance: 'well')
      sweep
      expect([hero.parent, hero.x, hero.y]).to eq([rooms[:town].actors, 30, 40])
    end

    it 'takes the node from its parent first' do
      holder = world.add_node(RGame::Engine::Node2D.new)
      holder.add_node(hero)
      rooms.move(hero, to: :town, entrance: 'gate')
      sweep
      expect(holder.children).to be_empty
    end

    it 'moves every node of an Array' do
      rooms.move([hero, other_hero], to: :town, entrance: 'gate')
      sweep
      expect(rooms[:town].arrivals.map(&:first)).to eq([hero, other_hero])
    end

    it 'raises KeyError for a name it was not given, when asked' do
      expect { rooms.move(hero, to: :cellar) }.to raise_error(KeyError, /no room named :cellar/)
    end

    it 'refuses what is not a node, before asking for any' do
      expect { rooms.move([hero, :bob], to: :town) }.to raise_error(TypeError, /:bob/)
      expect(rooms.pending?).to be(false)
    end

    it 'raises when the builder builds something that is not a room' do
      rooms.define(:shed) { RGame::Engine::Node2D.new }
      rooms.move(hero, to: :shed)
      expect { sweep }.to raise_error(TypeError, /built a RGame::Engine::Node2D/)
    end

    it 'raises when _arrive leaves the node outside the room' do
      rooms.define(:void) { RGame::Engine::Scene::Room.new }
      rooms.move(hero, to: :void)
      expect { sweep }.to raise_error(/_arrive left RGame::Engine::Node2D outside the room/)
    end
  end

  # Rule 2.
  describe 'whose move it is' do
    it 'stands the player the node\'s input_owner names in the room' do
      rooms.move(other_hero, to: :town, entrance: 'gate')
      sweep
      expect([rooms.room_of(first), rooms.room_of(second), rooms[:town].players]).to eq([nil, rooms[:town], [second]])
    end

    it 'finds the player through the node\'s parents' do
      holder = RGame::Engine::Node2D.new(input_owner: second)
      holder.add_node(RGame::Engine::Node2D.new)
      rooms.move(holder.children.first, to: :town, entrance: 'gate')
      sweep
      expect(rooms.room_of(second)).to be(rooms[:town])
    end

    it 'means the primary player for a node nobody owns' do
      rooms.move(RGame::Engine::Node2D.new, to: :town, entrance: 'gate')
      sweep
      expect(rooms.room_of(first)).to be(rooms[:town])
    end

    it 'stands nobody anywhere for a node everyone owns, so its room is freed' do
      rooms.move(RGame::Engine::Node2D.new(input_owner: players.everyone), to: :town, entrance: 'gate')
      sweep
      expect([rooms.room_of(first), rooms[:town]]).to eq([nil, nil])
    end
  end

  # Rule 5.
  describe 'a move to the room the node stands in' do
    let(:attached) { [] }

    before do
      calls = attached
      component = Class.new(RGame::Engine::Component) do
        define_method(:_attach) { calls << :attach }
        define_method(:_detach) { calls << :detach }
      end
      hero.add_component(component.new)
      rooms.move(hero, to: :town, entrance: 'gate')
      sweep
      attached.clear
    end

    it 'calls _arrive again in the same room' do
      town = rooms[:town]
      rooms.move(hero, to: :town, entrance: 'well')
      sweep
      expect([rooms[:town], town.arrivals.map(&:last), hero.x]).to eq([town, %w[gate well], 30])
    end

    it 'leaves the node in the tree, so its components keep their systems' do
      rooms.move(hero, to: :town, entrance: 'well')
      sweep
      expect([attached, hero.in_tree?]).to eq([[], true])
    end
  end

  # Rule 6.
  describe 'which rooms run' do
    it 'frees a room in the sweep its last player leaves it' do
      rooms.move(hero, to: :town, entrance: 'gate')
      sweep
      town = rooms[:town]
      rooms.move(hero, to: :garden, entrance: 'gate')
      sweep
      expect([rooms[:town], town.in_tree?, town.parent]).to eq([nil, false, nil])
    end

    it 'keeps a room another player still stands in' do
      rooms.move([hero, other_hero], to: :town, entrance: 'gate')
      sweep
      rooms.move(hero, to: :garden, entrance: 'gate')
      sweep
      expect([rooms[:town].players, rooms[:garden].players]).to eq([[second], [first]])
    end

    it 'builds a room anew on a later move' do
      rooms.move(hero, to: :town, entrance: 'gate')
      sweep
      town = rooms[:town]
      rooms.move(hero, to: :garden, entrance: 'gate')
      sweep
      rooms.move(hero, to: :town, entrance: 'gate')
      sweep
      expect(rooms[:town]).not_to be(town)
    end

    it 'runs a held room with nobody in it, from the next sweep until released' do
      rooms.hold(:garden)
      asked = rooms[:garden]
      sweep
      held = rooms[:garden]
      rooms.release(:garden)
      sweep
      expect([asked, held.class, held.players, rooms[:garden]]).to eq([nil, SpecRoom, [], nil])
    end

    it 'keeps a held room its last player leaves' do
      rooms.hold(:town)
      rooms.move(hero, to: :town, entrance: 'gate')
      sweep
      rooms.move(hero, to: :garden, entrance: 'gate')
      sweep
      expect(rooms[:town].players).to eq([])
    end

    it 'raises KeyError for holding a name it was not given' do
      expect { rooms.hold(:cellar) }.to raise_error(KeyError)
    end
  end

  # Rule 7.
  describe 'each tick' do
    it 'controls and updates each running room once, in the order they were built' do
      rooms.move(other_hero, to: :garden, entrance: 'gate')
      sweep
      rooms.move(hero, to: :town, entrance: 'gate')
      sweep
      log.clear
      tick
      expect(log).to eq([%i[garden control], %i[town control], %i[garden update], %i[town update]])
    end

    it 'sweeps inside each room' do
      rooms.move(hero, to: :town, entrance: 'gate')
      sweep
      leaf = rooms[:town].actors.add_node(RGame::Engine::Node2D.new)
      leaf.queue_free
      sweep
      expect(rooms[:town].actors.children).to eq([hero])
    end
  end

  # Rule 10.
  describe 'a second move asked for a node before its first lands' do
    it 'replaces the first' do
      rooms.move(hero, to: :town, entrance: 'gate')
      rooms.move(hero, to: :garden, entrance: 'well')
      sweep
      expect([rooms[:town], rooms[:garden].arrivals]).to eq([nil, [[hero, 'well']]])
    end
  end

  # Rule 11.
  describe 'the signals' do
    let(:seen) { [] }

    before do
      rooms.on_requested { |node, name| seen << [:requested, node, name, rooms.pending?] }
      rooms.on_arrived { |node, room| seen << [:arrived, node, room.name, node.parent.equal?(room.actors)] }
    end

    it 'fires requested once per node as a move is asked for' do
      rooms.move([hero, other_hero], to: :town, entrance: 'gate')
      expect(seen).to eq([[:requested, hero, :town, true], [:requested, other_hero, :town, true]])
    end

    it 'fires arrived once per node as it lands, once _arrive placed it' do
      rooms.move([hero, other_hero], to: :town, entrance: 'gate')
      seen.clear
      sweep
      sweep
      expect(seen).to eq([[:arrived, hero, :town, true], [:arrived, other_hero, :town, true]])
    end
  end

  # The caller that uses both: rooms, and the map and collision systems each
  # room mounts. The garden's column 18 is solid, its left edge at x = 288.
  describe 'two players in two rooms, each with a map' do
    let(:room) do
      Class.new(RGame::Engine::Scene::Room) do
        attr_reader :ticks

        def initialize(rows, cameras)
          super()
          @rows = rows
          @cameras = cameras
          @ticks = 0
        end

        def _enter_tree
          components = RGame::Engine::Components
          map = WalledTileMap.build(@rows)
          add_component(components::TileWorld.new(map:, tilemap_id: :level, cameras: @cameras))
          add_component(components::CollisionWorld.new(cell_size: 64))
          @actors = add_node(RGame::Engine::WorldView.new)
        end

        def _arrive(node, _entrance)
          node.x = 256.0
          node.y = 100.0
          @actors.add_node(node)
        end

        def _update(_dt) = @ticks += 1

        def world = get_component(RGame::Engine::Components::CollisionWorld)
      end
    end
    let(:viewports) { RGame::Engine::Viewports.new(players, width: 320, height: 240) }
    let(:root) do
      RGame::Engine::Node2D.new.tap do |node|
        node.add_component(players)
        node.add_component(viewports)
      end
    end
    let(:body_hero) { mapped_hero(first) }
    let(:body_other) { mapped_hero(second) }

    def mapped_hero(player)
      components = RGame::Engine::Components
      RGame::Engine::Node2D.new(input_owner: player).tap do |node|
        node.add_component(components::BoxCollider.new(width: 16, height: 16, layer: :hero))
        node.add_component(components::CharacterBody.new(speed: 60.0, blocked_by: [:tiles]))
      end
    end

    def colliders_in(room)
      found = []
      room.world.query_box(0, 0, 640, 480) { found << it }
      found.uniq
    end

    def collider(hero) = hero.get_component(RGame::Engine::Components::BoxCollider)

    before do
      cameras = [first.camera, second.camera]
      town_rows = Array.new(12) { '.' * 40 }
      garden_rows = Array.new(12) { "#{'.' * 18}#." }
      rooms.define(:big_town) { room.new(town_rows, cameras) }
      rooms.define(:small_garden) { room.new(garden_rows, cameras) }
      rooms.move([body_hero, body_other], to: :big_town)
      tick
      rooms.move(body_other, to: :small_garden)
      tick
    end

    it 'takes the moving hero\'s collider out of the town\'s index and into the garden\'s' do
      tick
      expect([colliders_in(rooms[:big_town]), colliders_in(rooms[:small_garden])])
        .to eq([[collider(body_hero)], [collider(body_other)]])
    end

    it 'stops the moving hero at the garden\'s wall' do
      body_other.get_component(RGame::Engine::Components::CharacterBody).set_intent(1, 0)
      tick(40)
      expect(body_other.x).to eq(272.0)
    end

    it 'bounds each player\'s camera by the room they stand in' do
      expect([[first.camera.world_width, first.camera.world_height],
              [second.camera.world_width, second.camera.world_height]]).to eq([[640, 192], [320, 192]])
    end

    it 'keeps the town running for the player who stayed' do
      expect { tick(3) }.to change { rooms[:big_town].ticks }.by(3)
    end

    it 'draws each room only into the view of the player standing in it' do
      renderer = FakeRenderer.new
      root.draw(renderer, viewports.screen)
      expect(renderer.calls_to(:clipped).map(&:args)).to eq([[0, 0, 320, 120], [0, 120, 320, 120]])
    end
  end

  describe '#define' do
    it 'refuses a name defined twice' do
      expect { rooms.define(:town) { SpecRoom.new } }.to raise_error(ArgumentError, /already defined/)
    end

    it 'refuses a name that is not a Symbol' do
      expect { rooms.define('town') { SpecRoom.new } }.to raise_error(TypeError)
    end

    it 'refuses a builder that takes parameters' do
      expect { rooms.define(:shed) { |hero:| SpecRoom.new(hero) } }.to raise_error(ArgumentError, /takes parameters/)
    end

    it 'refuses a name with no builder' do
      expect { rooms.define(:shed) }.to raise_error(ArgumentError, /needs a block/)
    end
  end

  describe '#transition=' do
    it 'refuses anything but a Fade or nil' do
      expect { rooms.transition = 0.5 }.to raise_error(TypeError)
    end
  end

  describe 'a host leaving and entering the tree' do
    it 'takes its rooms with it, and brings them back' do
      rooms.move(hero, to: :town, entrance: 'gate')
      sweep
      town = rooms[:town]
      root.remove_node(world)
      left = town.in_tree?
      root.add_node(world)
      expect([left, town.in_tree?]).to eq([false, true])
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
