# frozen_string_literal: true

# Draws a 1x1 rect at its own origin, so a frame says where the node landed.
class SpecCameraMarker < RGame::Engine::Node2D
  def _draw(renderer, _view) = renderer.rect(0, 0, 1, 1)
end

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

  # The first frame can be drawn before the first tick, so the camera has to be
  # on the node from the moment it enters, not from its first update.
  it 'points the camera as the node enters the tree, before any update' do
    node.add_component(described_class.new(camera: camera))
    root.enter_tree
    expect(camera.target_x).to eq(100.0)
  end

  # A suspended node is still drawn, and a move between rooms places it while
  # it is suspended. The camera shows it where it was placed.
  it 'keeps following a suspended node wherever it is placed' do
    node.add_component(described_class.new(camera: camera))
    root.enter_tree
    node.suspend
    node.x = 300.0
    expect(camera.target_x).to eq(300.0)
  end

  describe 'as the node leaves the tree' do
    before do
      node.add_component(described_class.new(camera: camera))
      root.enter_tree
    end

    it 'leaves the camera where the node was' do
      node.x = 150.0
      root.remove_node(node)
      node.x = 900.0
      expect(camera.target_x).to eq(150.0)
    end

    it 'leaves a camera that something else has pointed since' do
      camera.center_on(40, 60)
      root.remove_node(node)
      expect([camera.target_x, camera.target_y]).to eq([40, 60])
    end

    it 'lets go when the component alone is removed' do
      node.remove_component(described_class)
      node.x = 900.0
      expect(camera.target_x).to eq(100.0)
    end
  end

  # A scene pushed over another may follow its own node with the same camera.
  # The scene below is not updated meanwhile; once uncovered, its first update
  # points the camera back at its node.
  it 'takes the camera back on its next update after another node held it' do
    node.add_component(described_class.new(camera: camera))
    root.enter_tree
    other = root.add_node(RGame::Engine::Node2D.new(x: 500.0, y: 0.0))
    other.add_component(described_class.new(camera: camera))
    root.remove_node(other)
    node.update(0.016)
    node.x = 120.0
    expect(camera.target_x).to eq(120.0)
  end

  # The platform updates the whole tree, resolves the cameras, then draws. A
  # camera that copied the node's position in `_update` read it before the
  # body's step when it came first, and drew the node a step off centre.
  describe 'beside the mover that moves the node' do
    let(:screen) do
      players = RGame::Engine::Players.new([RGame::Engine::Player.new(id: 0, camera: camera)])
      RGame::Engine::Node2D.new.tap do |top|
        top.add_component(players)
        top.add_component(RGame::Engine::Viewports.new(players, width: 640, height: 480))
      end
    end

    # A body at 60 px/s steps 1 px a tick.
    def walker(camera_first:)
      body = RGame::Engine::Components::CharacterBody.new(speed: 60.0)
      follow = described_class.new(camera: camera)
      SpecCameraMarker.new(x: 100.0, y: 200.0).tap do |walker|
        (camera_first ? [follow, body] : [body, follow]).each { walker.add_component(it) }
        screen.add_node(RGame::Engine::WorldView.new).add_node(walker)
        screen.enter_tree
      end
    end

    # One tick and one frame, in the platform's order, answering the screen x
    # the walker's rect landed on.
    def step_and_draw(walker)
      walker.get_component(RGame::Engine::Components::CharacterBody).set_intent(1.0, 0.0)
      screen.update(1.0 / 60)
      viewports = screen.get_component(RGame::Engine::Viewports)
      viewports.refresh
      renderer = FakeRenderer.new
      screen.draw(renderer, viewports.screen)
      rect = renderer.calls_to(:rect).first
      rect.transforms.select { it.name == :translated }.sum { it.args.first }
    end

    { 'added before the body' => true, 'added after the body' => false }.each do |order, camera_first|
      describe order do
        it 'draws the node at the centre of the view as it walks' do
          walking = walker(camera_first:)
          drawn = Array.new(3) { step_and_draw(walking) }
          expect([drawn, walking.x]).to eq([[320.0, 320.0, 320.0], 103.0])
        end

        it 'centres the camera on where the node is now' do
          walking = walker(camera_first:)
          step_and_draw(walking)
          expect(camera.x).to eq(walking.world_x - 320)
        end
      end
    end
  end
end
