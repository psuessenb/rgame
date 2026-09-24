# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::AnimatedSprite do
  # Distinct rows so the drawn row tells which animation was selected; 1 frame each so
  # the column stays put and a single draw reveals the choice.
  let(:animations) do
    {
      stand: { row: 0, frames: 1, fps: 1 },
      walk_right: { row: 1, frames: 1, fps: 1 },
      walk_left: { row: 2, frames: 1, fps: 1 },
      walk_up: { row: 3, frames: 1, fps: 1 },
      walk_down: { row: 4, frames: 1, fps: 1 }
    }
  end
  let(:node) { RGame::Engine::Node2D.new(x: 5.0, y: 7.0) }
  let(:body) { RGame::Engine::Components::CharacterBody.new(speed: 50.0) }
  let(:sprite) { described_class.new(sheet: :hero, z: 10) }
  let(:renderer) { instance_double(FakeRenderer, layered: nil) }

  before do
    # The component resolves its sheet from node.root.context.assets on attach.
    sheet = instance_double(FakeSheet, animations: animations, frame_width: 16, frame_height: 32)
    assets = instance_double(FakeAssets, sheet: sheet)
    node.context = instance_double(FakeGame, assets: assets)
    node.add_component(body)
    node.add_component(sprite)
    node.enter_tree
    allow(renderer).to receive(:sprite)
    # Every node opens a layer for its own drawing; this double has to yield or
    # nothing inside it runs.
    allow(renderer).to receive(:layered).and_yield
  end

  # Drive one frame for the given intent, then draw.
  def step(intent_x, intent_y)
    body.set_intent(intent_x, intent_y)
    sprite._update(0.0)
    sprite._draw(renderer, screen_view)
  end

  describe '#_attach' do
    it 'sizes the node to the resolved sheet frame' do
      expect([node.width, node.height]).to eq([16, 32])
    end
  end

  describe '#update selects the animation from the body intent' do
    it 'faces right while moving right' do
      step(1.0, 0.0)
      expect(renderer).to have_received(:sprite).with(:hero, 1, any_args)
    end

    it 'faces left while moving left' do
      step(-1.0, 0.0)
      expect(renderer).to have_received(:sprite).with(:hero, 2, any_args)
    end

    it 'faces up while moving up' do
      step(0.0, -1.0)
      expect(renderer).to have_received(:sprite).with(:hero, 3, any_args)
    end

    it 'faces down while moving down' do
      step(0.0, 1.0)
      expect(renderer).to have_received(:sprite).with(:hero, 4, any_args)
    end

    it 'stands still when there is no intent' do
      step(0.0, 0.0)
      expect(renderer).to have_received(:sprite).with(:hero, 0, any_args)
    end

    it 'lets horizontal win on a diagonal' do
      step(1.0, 1.0) # walk_right, not walk_down
      expect(renderer).to have_received(:sprite).with(:hero, 1, any_args)
    end

    # A stick, or a route segment, rarely points straight down: the larger axis decides.
    it 'faces down while moving mostly down' do
      step(-0.3, 0.9)
      expect(renderer).to have_received(:sprite).with(:hero, 4, any_args)
    end

    it 'faces left while moving mostly left' do
      step(-0.9, -0.3)
      expect(renderer).to have_received(:sprite).with(:hero, 2, any_args)
    end
  end

  # Any mover is a facing source, and a PathFollow is the one with no intent to read: it faces
  # the road it is on.
  describe 'beside a PathFollow' do
    # A walker on a 100 px rightward road, taking one step of `dt` and drawing it.
    def walk_and_draw(dt)
      follow = RGame::Engine::Components::PathFollow.new(path: RGame::Engine::Path.new([[0.0, 0.0], [100.0, 0.0]]),
                                                         speed: 50.0)
      walker_sprite = described_class.new(sheet: :hero)
      walker = RGame::Engine::Node2D.new
      walker.context = node.context
      walker.add_component(follow)
      walker.add_component(walker_sprite)
      walker.enter_tree
      follow._update(dt)
      walker_sprite._update(dt)
      walker_sprite._draw(renderer, screen_view)
    end

    it 'walks right along a rightward segment' do
      walk_and_draw(0.5)
      expect(renderer).to have_received(:sprite).with(:hero, 1, any_args)
    end

    it 'stands once the road is walked' do
      walk_and_draw(10.0)
      expect(renderer).to have_received(:sprite).with(:hero, 0, any_args)
    end
  end

  # Two movers both write the position, so there is no telling which way the node faces.
  it 'refuses a node with two movers, naming both' do
    crowded = RGame::Engine::Node2D.new
    crowded.context = node.context
    crowded.add_component(RGame::Engine::Components::CharacterBody.new(speed: 50.0))
    crowded.add_component(RGame::Engine::Components::PathFollow.new(speed: 50.0))
    crowded.add_component(described_class.new(sheet: :hero))
    expect { crowded.enter_tree }
      .to raise_error(ArgumentError, /AnimatedSprite reads one .*Mover .* has 2: .*CharacterBody, .*PathFollow/)
  end

  describe '#draw' do
    it 'draws at the node resolved world origin with the configured layer and no flip' do
      body.set_intent(0.0, 0.0)
      node.update(0.0) # resolves world_x/world_y; zero intent so the body makes no move
      node.draw(renderer, screen_view)
      expect(renderer).to have_received(:sprite)
        .with(:hero, 0, anything, node.world_x, node.world_y, flip_x: false, z: 10)
    end

    it 'draws the picture lifted by the node elevation' do
      node.elevation = 6
      step(0.0, 0.0)
      expect(renderer).to have_received(:sprite).with(:hero, 0, anything, 0, -6, flip_x: false, z: 10)
    end

    it 'culls against the lifted box rather than the spot the node stands on' do
      node.elevation = 40 # the 32-tall frame now spans y -40..-8, above a view starting at 0
      step(0.0, 0.0)
      expect(renderer).not_to have_received(:sprite)
    end
  end

  # A 16x32 frame on a node at (100, 100), drawn through a FakeRenderer so the
  # frame's top-left corner is what the sheet was asked to draw at.
  describe 'anchor:' do
    def placed_node(elevation: 0)
      root = RGame::Engine::Node2D.new
      root.context = node.context
      root.add_node(RGame::Engine::Node2D.new(x: 100, y: 100)).tap { it.elevation = elevation }
    end

    def corner_drawn(anchor, elevation: 0)
      walker = placed_node(elevation: elevation)
      frames = FakeRenderer.new
      frames.register_sheet(:hero, FakeSheet.new(animations: animations, frame_width: 16, frame_height: 32))
      walker.add_component(RGame::Engine::Components::CharacterBody.new(speed: 50.0))
      walker.add_component(described_class.new(sheet: :hero, anchor: anchor))
      walker.parent.enter_tree
      walker.parent.update(0.0)
      walker.parent.draw(frames, screen_view)
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
      expect { described_class.new(sheet: :hero, anchor: :feet) }
        .to raise_error(ArgumentError, /:center, :bottom, :top_left.*:feet/)
    end
  end
end
