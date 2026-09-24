# frozen_string_literal: true

# The stack takes part in every tick: it controls, updates and draws its scenes
# and sweeps them. A tick with no switch pending or running is a per-frame path,
# so the stack itself may build nothing on it.
RSpec.describe RGame::Engine::Scene::SceneStack do
  def mounted
    root = RGame::Engine::Node2D.new
    stack = root.add_component(described_class.new)
    root.enter_tree
    stack.define(:below) { RGame::Engine::Node2D.new }
    stack.push(:below)
    root.sweep_freed
    stack.push(RGame::Engine::Node2D.new)
    root.sweep_freed
    [root, stack]
  end

  def tick(root, actions, renderer, view)
    root.control(actions)
    root.update(1.0 / 60)
    root.draw(renderer, view)
    root.sweep_freed
  end

  it 'allocates nothing on a tick with no switch asked for' do
    root, = mounted
    actions = RGame::Engine::Actions.new
    renderer = QuietRenderer.new
    view = screen_view

    expect { tick(root, actions, renderer, view) }.to allocate_nothing
  end
end
