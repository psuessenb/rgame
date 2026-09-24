# frozen_string_literal: true

# A running cutscene takes part in every tick: it reads its player's input for
# a confirm and a skip, and counts a wait or listens for a hold. A tick between
# two steps is a per-frame path, so the cutscene may build nothing on it.
RSpec.describe RGame::Engine::Components::Cutscene do
  # A player holding nothing, a solo view onto the stage, and a hero stopped.
  def mounted(script)
    map = RGame::Engine::InputMap.default.merge(skip: { buttons: [RGame::Util::Controls::KEY_TAB], hold: 0.5 })
    player = RGame::Engine::Player.new(id: 0, device: RGame::Util::Controls::KEYBOARD, input_map: map)
    players = RGame::Engine::Players.new([player])
    root = RGame::Engine::Node2D.new
    root.add_component(players)
    root.add_component(RGame::Engine::Viewports.new(players, width: 320, height: 240))
    stage = root.add_node(RGame::Engine::Node2D.new)
    hero = root.add_node(RGame::Engine::Node2D.new)
    root.enter_tree
    stage.add_component(described_class.new(script, context: stage, camera: RGame::Engine::Camera.new,
                                                    pause: [hero], skip: :skip))
    [root, players]
  end

  def tick(root, players, backend)
    players.poll(backend, 1.0 / 60)
    root.control(players)
    root.update(1.0 / 60)
    root.sweep_freed
  end

  # A tick of `script`, thirty ticks after it started.
  def running(script)
    root, players = mounted(RGame::Engine::Cutscene::Script.build(&script))
    backend = FakeInputBackend.new
    30.times { tick(root, players, backend) }
    -> { tick(root, players, backend) }
  end

  # The measure runs a thousand ticks, about seventeen seconds, so each step lasts longer.
  it 'allocates nothing a tick during a wait' do
    expect(&running(-> { wait 100 })).to allocate_nothing
  end

  it 'allocates nothing a tick during a hold' do
    expect(&running(-> { hold { it.add_component(RGame::Engine::Components::Tween.new(100)) } })).to allocate_nothing
  end

  it 'allocates nothing a tick while waiting for a press' do
    expect(&running(-> { press })).to allocate_nothing
  end
end
