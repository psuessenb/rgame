# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::WalkingSprite do
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
  # A scene holding the node, so the node's world position is its own and the
  # frame standing on it is in view.
  let(:node) { RGame::Engine::Node2D.new.add_node(RGame::Engine::Node2D.new(x: 50.0, y: 70.0)) }
  let(:body) { RGame::Engine::Components::CharacterBody.new(speed: 50.0) }
  let(:sprite) { described_class.new(sheet: :hero, z: 10) }
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

  # A node beside the scene, holding `components`, with the scene's assets.
  def lone_node(*components)
    lone = RGame::Engine::Node2D.new
    lone.context = scene.context
    components.each { lone.add_component(it) }
    lone
  end

  describe '#update selects the animation from the body intent' do
    before do
      node.add_component(body)
      node.add_component(sprite)
      scene.enter_tree
      scene.update(0.0) # resolves node.world_x/world_y; no intent yet, so the body stays put
    end

    # Drive one frame for the given intent, then draw.
    def step(intent_x, intent_y)
      body.set_intent(intent_x, intent_y)
      sprite._update(0.0)
      sprite._draw(renderer, screen_view)
    end

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
      follow = RGame::Engine::Components::PathFollow.new(path: RGame::Engine::Path.new([[0.0, 50.0], [100.0, 50.0]]),
                                                         speed: 50.0)
      walker_sprite = described_class.new(sheet: :hero)
      walker = scene.add_node(RGame::Engine::Node2D.new)
      walker.add_component(follow)
      walker.add_component(walker_sprite)
      scene.enter_tree
      scene.update(dt)
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

  describe 'attach' do
    it 'refuses a node with no mover' do
      expect { lone_node(described_class.new(sheet: :hero)).enter_tree }
        .to raise_error(RuntimeError, /WalkingSprite needs a .*Mover on the same node, and there is none/)
    end

    # Two movers both write the position, so there is no telling which way the node faces.
    it 'refuses a node with two movers, naming both' do
      crowded = lone_node(RGame::Engine::Components::CharacterBody.new(speed: 50.0),
                          RGame::Engine::Components::PathFollow.new(speed: 50.0),
                          described_class.new(sheet: :hero))
      expect { crowded.enter_tree }
        .to raise_error(ArgumentError, /WalkingSprite reads one .*Mover .* has 2: .*CharacterBody, .*PathFollow/)
    end

    # At attach rather than on the first step that way, which may be minutes into a game.
    it 'refuses a sheet missing a walk, naming it' do
      animations.delete(:walk_up)
      walker = lone_node(RGame::Engine::Components::CharacterBody.new(speed: 50.0), described_class.new(sheet: :hero))
      expect { walker.enter_tree }.to raise_error(ArgumentError, /has no animation :walk_up/)
    end
  end
end
