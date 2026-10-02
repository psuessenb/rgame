# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::Facing do
  # The walker hangs under a scene, so its world position is its own. Its body has no
  # speed: it turns on the spot, so every point below stays where the example put it.
  let(:scene) { RGame::Engine::Node2D.new.tap { it.scene = it } }
  let(:walker) { RGame::Engine::Node2D.new(x: 100.0, y: 100.0) }
  let(:body) { RGame::Engine::Components::CharacterBody.new(speed: 0.0) }
  let(:facing) { described_class.new }

  def components = RGame::Engine::Components
  def tick = scene.update(1.0 / 60)

  def enter(*own)
    own.each { walker.add_component(it) }
    scene.add_node(walker)
    scene.enter_tree
  end

  # Heads (x, y) for one tick, then stands still.
  def face(x, y)
    body.set_intent(x, y)
    tick
    body.set_intent(0.0, 0.0)
  end

  describe '#x and #y' do
    before { enter(body, facing) }

    it 'are 0, 0 before the mover heads anywhere' do
      tick
      expect([facing.x, facing.y]).to eq([0.0, 0.0])
    end

    it 'are the heading while the mover heads somewhere' do
      body.set_intent(-1.0, 0.0)
      tick
      expect([facing.x, facing.y]).to eq([-1.0, 0.0])
    end

    it 'keep the last heading once the mover stops' do
      face(0.0, -1.0)
      tick
      expect([facing.x, facing.y]).to eq([0.0, -1.0])
    end

    # Which of the two updates first is the add order, and a sibling between them
    # would see either. A heading set in `_control` counts before either update.
    it 'count a heading set this tick before any update runs' do
      face(0.0, -1.0)
      body.set_intent(1.0, 0.0)
      expect([facing.x, facing.y]).to eq([1.0, 0.0])
    end

    it 'keep the facing through a move to another parent' do
      face(-1.0, 0.0)
      scene.add_node(RGame::Engine::Node2D.new).add_node(walker)
      expect([facing.x, facing.y]).to eq([-1.0, 0.0])
    end
  end

  # PathFollow has no intent to read: it heads along the road, and 0, 0 once there.
  it 'keeps the road a PathFollow walked once it arrives' do
    road = RGame::Engine::Path.new([[0.0, 50.0], [0.0, 10.0]])
    enter(components::PathFollow.new(path: road, speed: 50.0), facing)
    scene.update(0.5)
    scene.update(10.0)
    expect([facing.x, facing.y]).to eq([0.0, -1.0])
  end

  describe '#in_front?' do
    before { enter(body, facing) }

    describe 'facing right' do
      before { face(1.0, 0.0) }

      it 'is true straight ahead' do
        expect(facing.in_front?(140.0, 100.0)).to be(true)
      end

      it 'is true at 45° either side, the boundary included' do
        expect([facing.in_front?(120.0, 80.0), facing.in_front?(120.0, 120.0)]).to eq([true, true])
      end

      it 'is false just past 45°' do
        expect([facing.in_front?(120.0, 79.0), facing.in_front?(120.0, 121.0)]).to eq([false, false])
      end

      it 'is false to the side, however near' do
        expect([facing.in_front?(100.0, 95.0), facing.in_front?(100.0, 105.0)]).to eq([false, false])
      end

      it 'is false behind' do
        expect(facing.in_front?(60.0, 100.0)).to be(false)
      end

      it "is false at the node's own origin" do
        expect(facing.in_front?(100.0, 100.0)).to be(false)
      end
    end

    it 'turns with a diagonal heading' do
      face(1.0, 1.0)
      expect([facing.in_front?(120.0, 120.0), facing.in_front?(120.0, 100.0), facing.in_front?(120.0, 80.0)])
        .to eq([true, true, false])
    end

    it 'is false everywhere while the node faces nowhere' do
      tick
      expect([facing.in_front?(140.0, 100.0), facing.in_front?(100.0, 60.0)]).to eq([false, false])
    end

    # Measured from the local origin, (80, 100) would be 30 px ahead.
    it "measures from the node's world origin" do
      scene.add_node(RGame::Engine::Node2D.new(x: 50.0)).add_node(walker)
      walker.x = 50.0
      face(1.0, 0.0)
      expect([facing.in_front?(80.0, 100.0), facing.in_front?(120.0, 100.0)]).to eq([false, true])
    end
  end

  describe '.new' do
    it 'starts facing where x: and y: say' do
      start = described_class.new(y: 1)
      enter(body, start)
      tick
      expect([start.x, start.y, start.in_front?(100.0, 140.0)]).to eq([0.0, 1.0, true])
    end
  end

  describe '#face' do
    it 'turns a node with no mover, and it stays turned' do
      enter(facing)
      facing.face(-1.0, 0.0)
      tick
      expect([facing.x, facing.y, facing.in_front?(60.0, 100.0)]).to eq([-1.0, 0.0, true])
    end

    it 'scales the direction so its larger axis is ±1' do
      enter(facing)
      facing.face(3, -6)
      expect([facing.x, facing.y]).to eq([0.5, -1.0])
    end

    it 'faces nowhere at (0, 0)' do
      enter(facing)
      facing.face(1.0, 0.0)
      facing.face(0, 0)
      expect([facing.x, facing.y, facing.in_front?(140.0, 100.0)]).to eq([0.0, 0.0, false])
    end

    it 'turns a node whose mover stands still' do
      enter(body, facing)
      face(1.0, 0.0)
      facing.face(0.0, 1.0)
      tick
      expect([facing.x, facing.y]).to eq([0.0, 1.0])
    end

    it 'gives way to the heading while the mover heads somewhere, and after it stops' do
      enter(body, facing)
      facing.face(0.0, 1.0)
      face(1.0, 0.0)
      tick
      expect([facing.x, facing.y]).to eq([1.0, 0.0])
    end
  end

  describe 'its mover' do
    it 'is found when added to a node in the tree after the Facing' do
      enter(facing)
      walker.add_component(body)
      body.set_intent(0.0, -1.0)
      expect([facing.x, facing.y]).to eq([0.0, -1.0])
    end

    it 'may not be one of two' do
      enter(body, components::PathFollow.new(speed: 50.0), facing)
      expect { tick }
        .to raise_error(ArgumentError, /Facing turns with one .*Mover .* has 2: .*CharacterBody, .*PathFollow/)
    end
  end

  # Facing right, a point behind or straight to the side multiplies a zero by a
  # negative, which is -0.0 and would allocate.
  it 'remembers and answers without allocating' do
    enter(body, facing)
    face(1.0, 0.0)
    expect do
      facing._update(1.0 / 60)
      facing.face(-1.0, 0.0)
      facing.in_front?(60.0, 100.0)
      facing.in_front?(100.0, 60.0)
      facing.x
      facing.y
    end.to allocate_nothing
  end
end
