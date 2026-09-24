# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::Sprite do
  subject(:sprite) { described_class.new(id: :ship, scale: 2.0, z: 3) }

  # Resolve abs coordinates by placing the node under a parent and running a phase.
  let(:node) { RGame::Engine::Node2D.new.add_node(RGame::Engine::Node2D.new(x: 5, y: 6)) }

  before do
    node.add_component(sprite)
    node.parent.update(0.0) # resolve node.world_x/world_y (only `update` resolves the transform)
  end

  describe '#draw' do
    let(:renderer) { instance_double(FakeRenderer) }

    it 'draws the image at its own origin, with no angle (the node places and rotates it)' do
      allow(renderer).to receive(:image)
      sprite._draw(renderer, screen_view)
      # Neither a position nor an angle: Node2D#draw has already pushed this node's
      # transform, so (0, 0) *is* the node, correctly rotated. Passing either would
      # apply it a second time. The node is at (5, 6) and draws at (0, 0).
      expect(renderer).to have_received(:image).with(:ship, 0, 0, scale: 2.0, z: 3)
    end

    it 'draws the image lifted by the node elevation' do
      allow(renderer).to receive(:image)
      node.elevation = 9
      sprite._draw(renderer, screen_view)
      expect(renderer).to have_received(:image).with(:ship, 0, -9, scale: 2.0, z: 3)
    end
  end

  # A 20x30 picture drawn at twice its size, on a node at (100, 100): the
  # renderer takes the picture's centre, so each anchor shows as where that is.
  describe 'anchor:' do
    let(:renderer) { FakeRenderer.new.tap { it.register_image(:ship, StubImage.new(20, 30)) } }

    def centre_drawn(anchor, elevation: 0)
      root = RGame::Engine::Node2D.new
      placed = root.add_node(RGame::Engine::Node2D.new(x: 100, y: 100, width: 20, height: 30))
      placed.elevation = elevation
      placed.add_component(described_class.new(id: :ship, scale: 2.0, anchor: anchor))
      root.draw(renderer, screen_view)
      renderer.calls_to(:image).last.args.drop(1)
    end

    it 'puts the centre of the picture on the origin for :center' do
      expect(centre_drawn(:center)).to eq([0, 0])
    end

    it 'puts the bottom centre of the picture on the origin for :bottom' do
      expect(centre_drawn(:bottom)).to eq([0, -30])
    end

    it 'puts the top-left corner of the picture on the origin for :top_left' do
      expect(centre_drawn(:top_left)).to eq([20, 30])
    end

    it 'lifts the picture by the node elevation for every anchor' do
      expect(%i[center bottom top_left].map { centre_drawn(it, elevation: 5) })
        .to eq([[0, -5], [0, -35], [20, 25]])
    end

    it 'spins a :center picture in place, since the node rotates about its origin' do
      root = RGame::Engine::Node2D.new
      root.add_node(RGame::Engine::Node2D.new(x: 100, y: 100, width: 20, height: 30, angle: Math::PI / 2))
          .add_component(described_class.new(id: :ship, anchor: :center))
      root.draw(renderer, screen_view)

      drawn = renderer.calls_to(:image).last
      rotation = drawn.transforms.find { it.name == :rotated }
      expect(drawn.args.drop(1)).to eq([0, 0])
      expect(rotation.args).to eq([90.0, 0, 0])
    end

    it 'raises at construction for an unknown anchor, naming the three' do
      expect { described_class.new(id: :ship, anchor: :feet) }
        .to raise_error(ArgumentError, /:center, :bottom, :top_left.*:feet/)
    end
  end
end
