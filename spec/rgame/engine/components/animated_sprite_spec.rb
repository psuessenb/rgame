# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::AnimatedSprite do
  # Distinct rows, so the drawn row tells which animation plays. `spin` and
  # `roll` have four frames of a quarter second each, so the drawn column tells
  # how far in it is.
  let(:animations) do
    {
      stand: { row: 0, frames: 1, fps: 1 },
      spin: { row: 1, frames: 4, fps: 4 },
      roll: { row: 2, frames: 4, fps: 4 }
    }
  end
  # A scene holding the node, so the node's world position is its own and the
  # frame standing on it is in view. The node has no Mover.
  let(:node) { RGame::Engine::Node2D.new.add_node(RGame::Engine::Node2D.new(x: 50.0, y: 70.0)) }
  let(:sprite) { described_class.new(sheet: :hero, animation: :stand, z: 10) }
  let(:renderer) { instance_double(FakeRenderer, layered: nil, translated: nil) }

  before do
    # The component resolves its sheet from node.root.context.assets on attach.
    sheet = instance_double(FakeSheet, animations: animations, frame_width: 16, frame_height: 32)
    assets = instance_double(FakeAssets, sheet: sheet)
    scene.context = instance_double(FakeGame, assets: assets)
    allow(renderer).to receive(:sprite)
    # Every node opens a layer for its own drawing; this double has to yield or
    # nothing inside it runs.
    allow(renderer).to receive(:layered).and_yield
    allow(renderer).to receive(:translated).and_yield
  end

  def scene = node.parent

  # Adds `component` to the node, enters the tree, and resolves the node's
  # world position.
  def mount(component = sprite)
    node.add_component(component)
    scene.enter_tree
    scene.update(0.0)
    component
  end

  # Advances the sprite by `dt` and draws it.
  def step(dt = 0.0, component = sprite)
    component._update(dt)
    component._draw(renderer, screen_view)
  end

  describe '#_attach' do
    it 'sizes the node to the resolved sheet frame' do
      mount
      expect([node.width, node.height]).to eq([16, 32])
    end
  end

  describe 'animation:' do
    it 'draws that animation on a node with no Mover' do
      spinning = mount(described_class.new(sheet: :hero, animation: :spin))
      step(0.0, spinning)
      expect(renderer).to have_received(:sprite).with(:hero, 1, 0, any_args)
    end

    it 'raises at attach for a name the sheet lacks, listing the ones it has' do
      expect { mount(described_class.new(sheet: :hero, animation: :fly)) }
        .to raise_error(ArgumentError, /:hero has no animation :fly\. It has :stand, :spin, :roll/)
    end

    it 'raises at attach for a name played before it' do
      waiting = described_class.new(sheet: :hero, animation: :spin)
      waiting.play(:fly)
      expect { mount(waiting) }.to raise_error(ArgumentError, /has no animation :fly/)
    end
  end

  describe '#play' do
    let(:sprite) { described_class.new(sheet: :hero, animation: :spin) }

    before do
      mount
      step(0.5) # two quarters into spin: column 2
    end

    it 'starts another animation from its first frame' do
      sprite.play(:roll)
      step
      expect(sprite.animation).to eq(:roll)
      expect(renderer).to have_received(:sprite).with(:hero, 2, 0, any_args)
    end

    it 'carries on with the animation already playing' do
      sprite.play(:spin)
      step(0.25)
      expect(renderer).to have_received(:sprite).with(:hero, 1, 3, any_args)
    end

    it 'raises for a name the sheet lacks, listing the ones it has, and keeps playing' do
      expect { sprite.play(:fly) }.to raise_error(ArgumentError, /has no animation :fly\. It has :stand, :spin, :roll/)
      expect(sprite.animation).to eq(:spin)
    end
  end

  describe '#_choose_animation' do
    # A sprite told what to play through the hook, as a subclass is.
    let(:chooser) do
      Class.new(described_class) do
        attr_accessor :choice

        def _choose_animation = choice
      end
    end

    it 'plays what it returns, and draws it on the same tick' do
      choosing = mount(chooser.new(sheet: :hero, animation: :stand))
      choosing.choice = :spin
      step(0.25, choosing)
      expect(renderer).to have_received(:sprite).with(:hero, 1, 1, any_args)
    end

    it 'carries on when it returns nil' do
      choosing = mount(chooser.new(sheet: :hero, animation: :roll))
      step(0.5, choosing)
      expect(renderer).to have_received(:sprite).with(:hero, 2, 2, any_args)
    end
  end

  describe '#draw' do
    before { mount }

    it 'draws the frame standing on the node origin, with the configured layer and no flip' do
      scene.draw(renderer, screen_view)
      expect(renderer).to have_received(:sprite).with(:hero, 0, 0, -8, -32, flip_x: false, z: 10)
    end

    it 'draws the picture lifted by the node elevation' do
      node.elevation = 6
      step
      expect(renderer).to have_received(:sprite).with(:hero, 0, 0, -8, -38, flip_x: false, z: 10)
    end

    it 'culls against the lifted box rather than the spot the node stands on' do
      node.elevation = 80 # the 32-tall frame now spans y -42..-10, above a view starting at 0
      step
      expect(renderer).not_to have_received(:sprite)
    end
  end

  # A 16x32 frame on a node at (100, 100), drawn through a FakeRenderer so the
  # frame's top-left corner is what the sheet was asked to draw at.
  describe 'anchor:' do
    def placed_node(elevation: 0)
      root = RGame::Engine::Node2D.new
      root.context = scene.context
      root.add_node(RGame::Engine::Node2D.new(x: 100, y: 100)).tap { it.elevation = elevation }
    end

    def corner_drawn(anchor, elevation: 0)
      standing = placed_node(elevation: elevation)
      frames = FakeRenderer.new
      frames.register_sheet(:hero, FakeSheet.new(animations: animations, frame_width: 16, frame_height: 32))
      standing.add_component(described_class.new(sheet: :hero, animation: :stand, anchor: anchor))
      standing.parent.enter_tree
      standing.parent.update(0.0)
      standing.parent.draw(frames, screen_view)
      frames.calls_to(:image_at).last.args.drop(1)
    end

    it 'puts the top-left corner of the frame on the origin for :top_left' do
      expect(corner_drawn(:top_left)).to eq([0, 0])
    end

    it 'puts the bottom centre of the frame on the origin for :bottom' do
      expect(corner_drawn(:bottom)).to eq([-8, -32])
    end

    it 'puts the centre of the frame on the origin for :center' do
      expect(corner_drawn(:center)).to eq([-8, -16])
    end

    it 'lifts the frame by the node elevation for every anchor' do
      expect(%i[center bottom top_left].map { corner_drawn(it, elevation: 5) })
        .to eq([[-8, -21], [-8, -37], [0, -5]])
    end

    # The two components draw differently, a Sprite by its centre and a sheet
    # frame by its corner, so the pixels they cover are the thing to compare.
    it 'covers the same pixels as a Sprite of the same size and anchor' do
      pictures = FakeRenderer.new.tap { it.register_image(:ship, StubImage.new(16, 32)) }
      covered = %i[center bottom top_left].map do |anchor|
        still = placed_node
        still.width = 16
        still.height = 32
        still.add_component(RGame::Engine::Components::Sprite.new(id: :ship, anchor: anchor))
        still.parent.draw(pictures, screen_view)
        _, centre_x, centre_y = pictures.calls_to(:image).last.args
        [centre_x - 8, centre_y - 16]
      end

      expect(covered).to eq(%i[center bottom top_left].map { corner_drawn(it) })
    end

    it 'raises at construction for an unknown anchor, naming the three' do
      expect { described_class.new(sheet: :hero, animation: :stand, anchor: :feet) }
        .to raise_error(ArgumentError, /:center, :bottom, :top_left.*:feet/)
    end
  end
end
