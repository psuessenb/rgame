# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::CameraFollow do
  let(:camera) { RGame::Engine::Camera.new }

  # A followed node always hangs inside a scene, never at the top: Node2D pins a
  # parentless node to the origin, so a node driving a camera needs a root above
  # it for its absolute position to mean anything.
  let(:root) { RGame::Engine::Node2D.new }
  let(:node) { root.add_node(RGame::Engine::Node2D.new(x: 100.0, y: 200.0)) }

  def follow(**)
    node.add_component(described_class.new(camera: camera, **))
    root.enter_tree
    root.update(0.016)
  end

  it 'points the camera at the node it is attached to' do
    follow
    expect([camera.target_x, camera.target_y]).to eq([100.0, 200.0])
  end

  it 'shifts the target by the offset, for a node whose origin is not its middle' do
    follow(offset_x: 8.0, offset_y: 24.0)
    expect([camera.target_x, camera.target_y]).to eq([108.0, 224.0])
  end

  it 'follows the node as it moves' do
    follow
    node.x = 300.0
    root.update(0.016)
    expect(camera.target_x).to eq(300.0)
  end

  # It reads the absolute origin, so a followed node nested under an offset
  # parent is tracked in world space rather than its parent's.
  it 'follows the absolute position, not the parent-relative one' do
    branch = root.add_node(RGame::Engine::Node2D.new(x: 1000.0, y: 0.0))
    nested = branch.add_node(RGame::Engine::Node2D.new(x: 50.0, y: 0.0))
    nested.add_component(described_class.new(camera: camera))
    root.enter_tree
    root.update(0.016)

    expect(camera.target_x).to eq(1050.0)
  end

  # The whole point of the camera living on the player rather than in the world:
  # "player two's camera follows player two" is this component with their camera.
  it 'points whichever camera it was given, so two nodes drive two cameras' do
    one = RGame::Engine::Player.new(id: 0)
    two = RGame::Engine::Player.new(id: 1)
    root.add_node(RGame::Engine::Node2D.new(x: 10.0, y: 0.0))
        .add_component(described_class.new(camera: one.camera))
    root.add_node(RGame::Engine::Node2D.new(x: 20.0, y: 0.0))
        .add_component(described_class.new(camera: two.camera))
    root.enter_tree
    root.update(0.016)

    expect([one.camera.target_x, two.camera.target_x]).to eq([10.0, 20.0])
  end
end
