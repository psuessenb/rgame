# frozen_string_literal: true

# Respawn and Scene::Rooms, composed: a hero with every part of a fall, in a
# world of two rooms that each have gaps. Each part has its own spec, and no
# example or test project mounts Respawn beside Rooms, so this is where the two
# meet.
#
# Room :a has gap cells at x 32 to 64, y 32 to 48, and its gate at (24, 24) is
# on ground. Room :b has gap cells at x 16 to 48, y 16 to 32, under where :a's
# gate would be, and its door at (56, 24) is on ground just right of them. A
# tick is a 60th of a second, and a move fades for a quarter of a second each
# way.
RSpec.describe 'Respawn across rooms' do # rubocop:disable RSpec/DescribeClass -- a composition of Respawn, Fall, Footing and Scene::Rooms, not one class
  let(:players) { RGame::Engine::Players.new([RGame::Engine::Player.new(id: 0, device: RGame::Util::Controls::KEYBOARD)]) }
  let(:root) { RGame::Engine::Node2D.new.tap { it.add_component(players) } }
  let(:rooms) do
    world = root.add_node(RGame::Engine::Node2D.new).tap { it.scene = it }
    world.add_component(RGame::Engine::Scene::Rooms.new)
  end
  let(:hero) do
    RGame::Engine::Node2D.new(input_owner: player).tap do |node|
      node.add_component(parts::FeetCollider.new(width: 12, height: 6))
      node.add_component(parts::CharacterBody.new(speed: 60, blocked_by: [:tiles]))
      node.add_component(parts::Footing.new(coyote: 0))
      node.add_component(parts::Fall.new(duration: 0.25))
      node.add_component(parts::Respawn.new)
    end
  end
  let(:seen) { [] }

  def parts = RGame::Engine::Components
  def player = players.primary
  def room_of(node) = RGame::Engine::Scene::Room.of(node)&.name

  def tick
    players.poll(FakeInputBackend.new, 1.0 / 60)
    root.control(players)
    root.update(1.0 / 60)
    root.sweep_freed
  end

  # Ticks until the block answers true, and answers how many ticks that took.
  def tick_until(limit = 240)
    took = (1..limit).find do
      tick
      yield
    end
    took || raise("still waiting after #{limit} ticks")
  end

  def go(to:, location:)
    rooms.move(hero, to:, location:)
    tick_until { !rooms.pending? && !rooms.transitioning? }
  end

  # Walks the hero left from the door into :b's gap. It stops walking as it
  # falls, so it stands still wherever it comes back.
  def walk_into_the_gap
    body = hero.get_component(parts::CharacterBody)
    hero.get_component(parts::Fall).on_fell { body.set_intent(0, 0) }
    body.set_intent(-1, 0)
    tick_until { hero.get_component(parts::Fall).falling? }
  end

  before do
    rooms.define(:a) { MappedRoom.new(['....', '....', '..~~'], objects: [['gate', 24, 24]]) }
    rooms.define(:b) { MappedRoom.new(['....', '.~~.', '....'], objects: [['door', 56, 24]]) }
    rooms.transition = RGame::Engine::Scene::Fade.new(cover: 0.25, reveal: 0.25)
    root.enter_tree
    fall = hero.get_component(parts::Fall)
    fall.on_fell { seen << :fell }
    fall.on_finished { seen << :finished }
    hero.get_component(parts::Respawn).on_respawned { seen << [:respawned, room_of(hero), hero.world_x, hero.world_y] }
    rooms.on_arrived { |_, room| seen << [:arrived, room.name] }
  end

  it 'brings a hero who falls in :b back at the gate in :a, where it first landed' do
    pending 'a respawn point in a room'
    go(to: :a, location: 'gate')
    go(to: :b, location: 'door')
    seen.clear
    walk_into_the_gap
    tick_until { !hero.get_component(parts::Fall).falling? }
    tick_until { !rooms.pending? && !rooms.transitioning? }

    expect([room_of(hero), hero.world_x, hero.world_y, rooms.room_of(player)&.name, rooms[:b]])
      .to eq([:a, 24.0, 24.0, :a, nil])
    expect(seen).to eq([:fell, :finished, [:respawned, :a, 24.0, 24.0], %i[arrived a]])
  end

  it 'brings a hero who falls in the room it first landed in back at once, under no cover' do
    go(to: :b, location: 'door')
    seen.clear
    walk_into_the_gap
    tick_until { !hero.get_component(parts::Fall).falling? }

    expect([room_of(hero), hero.world_x, hero.world_y, rooms.pending?, rooms.transitioning?])
      .to eq([:b, 56.0, 24.0, false, false])
    expect(seen).to eq([:fell, [:respawned, :b, 56.0, 24.0], :finished])
  end
end
