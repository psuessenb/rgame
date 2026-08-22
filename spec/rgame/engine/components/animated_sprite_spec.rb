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
  let(:body) { RGame::Engine::Components::CharacterBody.new(feet_width: 8, feet_height: 6, speed: 50.0) }
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
    sprite.update(0.0)
    sprite.draw(renderer, screen_view)
  end

  describe '#on_attach' do
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
  end

  describe '#draw' do
    it 'draws at the node resolved world origin with the configured layer and no flip' do
      body.set_intent(0.0, 0.0)
      node.update(0.0) # resolves abs_x/abs_y; zero intent so the body makes no move
      node.draw(renderer, screen_view)
      expect(renderer).to have_received(:sprite)
        .with(:hero, 0, anything, node.abs_x, node.abs_y, flip_x: false, z: 10)
    end
  end
end
