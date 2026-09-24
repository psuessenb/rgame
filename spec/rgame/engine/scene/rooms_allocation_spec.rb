# frozen_string_literal: true

# The rooms take part in every tick: they control, update, draw and sweep each
# running room, and each player's cover. A tick with no move pending or under
# way is a per-frame path, so the rooms may build nothing on it.
RSpec.describe RGame::Engine::Scene::Rooms do
  # Two players in two rooms, each room with a WorldView drawn into two views.
  # A move has run under a transition and ended, so both covers exist.
  def mounted
    first = RGame::Engine::Player.new(id: 0, device: RGame::Util::Controls::KEYBOARD)
    second = RGame::Engine::Player.new(id: 1, device: RGame::Util::Controls.gamepad(0))
    players = RGame::Engine::Players.new([first, second])
    root = RGame::Engine::Node2D.new
    root.add_component(players)
    root.add_component(RGame::Engine::Viewports.new(players, width: 320, height: 240))
    world = root.add_node(RGame::Engine::Node2D.new)
    world.scene = world
    rooms = world.add_component(described_class.new)
    rooms.define(:town) { SpecRoom.new }
    rooms.define(:garden) { SpecRoom.new }
    rooms.transition = RGame::Engine::Scene::Fade.new(cover: 0.1, reveal: 0.1)
    root.enter_tree
    rooms.move(RGame::Engine::Node2D.new(input_owner: first), to: :town, entrance: 'gate')
    rooms.move(RGame::Engine::Node2D.new(input_owner: second), to: :garden, entrance: 'gate')
    [root, players]
  end

  def tick(root, players, renderer, view)
    root.control(players)
    root.update(1.0 / 60)
    root.draw(renderer, view)
    root.sweep_freed
  end

  it 'allocates nothing on a tick with no move asked for, with two rooms running' do
    root, players = mounted
    renderer = QuietRenderer.new
    view = screen_view
    30.times { tick(root, players, renderer, view) }

    expect { tick(root, players, renderer, view) }.to allocate_nothing
  end
end
