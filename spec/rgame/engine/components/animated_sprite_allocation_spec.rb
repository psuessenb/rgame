# frozen_string_literal: true

# A sprite updates and draws every frame, for every animated node in view, so
# neither may allocate once warm. Each measurement runs 1,000 ticks at 60 a
# second, which passes every frame of each animation many times over: a frame
# that only some ticks reach cannot hide.
RSpec.describe RGame::Engine::Components::AnimatedSprite do
  let(:scene) do
    sheet = FakeSheet.new(animations: { stand: { row: 0, frames: 1, fps: 1 },
                                        spin: { row: 1, frames: 4, fps: 8 },
                                        walk_right: { row: 2, frames: 6, fps: 8 },
                                        walk_left: { row: 2, frames: 6, fps: 8, flip_x: true },
                                        walk_up: { row: 3, frames: 6, fps: 8 },
                                        walk_down: { row: 4, frames: 6, fps: 8 } },
                          frame_width: 16, frame_height: 22)
    RGame::Engine::Node2D.new.tap { it.context = FakeGame.new(assets: FakeAssets.new(sheets: { 'hero.json' => sheet })) }
  end
  let(:renderer) { QuietRenderer.new }
  let(:view) { screen_view }

  # A node holding `components`, in the tree, and the last of them.
  def mount(*components)
    node = scene.add_node(RGame::Engine::Node2D.new(x: 100.0, y: 100.0))
    components.each { node.add_component(it) }
    scene.enter_tree
    scene.update(0.0)
    components.last
  end

  def tick(sprite)
    sprite._update(1.0 / 60)
    sprite._draw(renderer, view)
  end

  it 'plays an animation without allocating, on every frame of it' do
    sprite = mount(described_class.new(sheet: 'hero.json', animation: :spin))

    expect { tick(sprite) }.to allocate_nothing
  end

  describe RGame::Engine::Components::WalkingSprite do
    let(:body) { RGame::Engine::Components::CharacterBody.new(speed: 50.0) }
    let(:sprite) { mount(body, described_class.new(sheet: 'hero.json')) }

    it 'walks without allocating, on every frame of the walk' do
      body.set_intent(1.0, 0.0)

      expect { tick(sprite) }.to allocate_nothing
    end

    it 'stands without allocating' do
      expect { tick(sprite) }.to allocate_nothing
    end

    # Each turn plays another animation from its first frame.
    it 'turns without allocating' do
      turns = 0

      expect do
        turns += 1
        body.set_intent(turns.even? ? 1.0 : -1.0, 0.0)
        tick(sprite)
      end.to allocate_nothing
    end
  end
end
