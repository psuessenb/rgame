# frozen_string_literal: true

RSpec.describe RGame::Engine::Scene::SceneStack do
  # The stack is a component, so it reaches the tree through its host node: push
  # wires each scene under that node, pop detaches it. Attach the stack to a real
  # node so `node` resolves to `host`.
  subject(:stack) { host.add_component(described_class.new) }

  let(:host) { RGame::Engine::Node2D.new }

  # Scenes are plain nodes, so a verified double of Node2D exercises exactly the
  # surface the stack drives: the enter_tree/exit_tree cascade, the parent + scene-
  # boundary wiring, and the per-phase control/update/draw forwarding.
  def scene_double
    instance_double(RGame::Engine::Node2D, enter_tree: nil, exit_tree: nil, :parent= => nil,
                                           :scene= => nil, :sibling_order= => nil)
  end

  describe '#current' do
    it 'is nil while the stack is empty' do
      expect(stack.current).to be_nil
    end

    it 'is the most recently pushed scene' do
      first  = scene_double
      second = scene_double
      stack.push(first)
      stack.push(second)
      expect(stack.current).to be(second)
    end
  end

  describe '#push' do
    let(:scene) { scene_double }

    it 'returns the stack for chaining' do
      expect(stack.push(scene)).to be(stack)
    end

    it 'makes the scene current' do
      stack.push(scene)
      expect(stack.current).to be(scene)
    end

    it 'brings the scene into the tree' do
      stack.push(scene)
      expect(scene).to have_received(:enter_tree)
    end

    it 'wires the scene under the host node and marks it as its own scene boundary' do
      stack.push(scene)
      expect(scene).to have_received(:parent=).with(host)
      expect(scene).to have_received(:scene=).with(scene)
    end

    it 'keeps the previous scene underneath' do
      first = scene_double
      stack.push(first)
      stack.push(scene)
      stack.pop
      expect(stack.current).to be(first)
    end
  end

  describe '#pop' do
    it 'returns the stack for chaining' do
      stack.push(scene_double)
      expect(stack.pop).to be(stack)
    end

    it 'removes the current scene' do
      scene = scene_double
      stack.push(scene)
      stack.pop
      expect(stack.current).to be_nil
    end

    it 'takes the popped scene out of the tree' do
      scene = scene_double
      stack.push(scene)
      stack.pop
      expect(scene).to have_received(:exit_tree)
    end

    it 'detaches the popped scene from the tree' do
      scene = scene_double
      stack.push(scene)
      stack.pop
      expect(scene).to have_received(:parent=).with(nil)
      expect(scene).to have_received(:scene=).with(nil)
    end

    it 'is a no-op on an empty stack' do
      expect(stack.pop).to be(stack)
      expect(stack.current).to be_nil
    end
  end

  describe '#replace' do
    let(:outgoing) { scene_double }
    let(:incoming) { scene_double }

    before { stack.push(outgoing) }

    it 'makes the new scene current' do
      stack.replace(incoming)
      expect(stack.current).to be(incoming)
    end

    it 'removes the outgoing scene' do
      stack.replace(incoming)
      expect(outgoing).to have_received(:exit_tree)
    end

    it 'adds the incoming scene' do
      stack.replace(incoming)
      expect(incoming).to have_received(:enter_tree)
    end

    it 'does not leave the outgoing scene underneath' do
      stack.replace(incoming)
      stack.pop
      expect(stack.current).to be_nil
    end

    it 'still pushes when the stack is empty' do
      empty = described_class.new
      empty.replace(incoming)
      expect(empty.current).to be(incoming)
    end
  end

  describe '#control' do
    let(:actions) { instance_double(RGame::Engine::Actions) }

    it 'forwards to the current scene only' do
      below   = scene_double
      current = scene_double
      allow(below).to receive(:control)
      allow(current).to receive(:control)
      stack.push(below)
      stack.push(current)

      stack.control(actions)

      expect(current).to have_received(:control).with(actions)
      expect(below).not_to have_received(:control)
    end

    it 'does nothing on an empty stack' do
      expect { stack.control(actions) }.not_to raise_error
    end
  end

  describe '#update' do
    it 'forwards to the current scene only' do
      below   = scene_double
      current = scene_double
      allow(below).to receive(:update)
      allow(current).to receive(:update)
      stack.push(below)
      stack.push(current)

      stack.update(0.016)

      expect(current).to have_received(:update).with(0.016)
      expect(below).not_to have_received(:update)
    end

    it 'does nothing on an empty stack' do
      expect { stack.update(0.016) }.not_to raise_error
    end
  end

  describe '#sweep_freed' do
    it 'forwards the deferred-free sweep into the current scene' do
      scene = scene_double
      allow(scene).to receive(:sweep_freed)
      stack.push(scene)
      stack.sweep_freed
      expect(scene).to have_received(:sweep_freed)
    end

    it 'does nothing on an empty stack' do
      expect { stack.sweep_freed }.not_to raise_error
    end
  end

  describe '#draw' do
    let(:renderer) { instance_double(Object) }

    it 'draws every scene bottom-to-top so the current scene paints last' do
      drawn   = []
      below   = scene_double
      current = scene_double
      allow(below).to receive(:draw) { drawn << :below }
      allow(current).to receive(:draw) { drawn << :current }
      stack.push(below)
      stack.push(current)

      stack.draw(renderer, screen_view)

      expect(drawn).to eq(%i[below current])
    end

    it 'passes the renderer and the view to each scene' do
      scene = scene_double
      view = screen_view
      allow(scene).to receive(:draw)
      stack.push(scene)

      stack.draw(renderer, view)

      expect(scene).to have_received(:draw).with(renderer, view)
    end

    it 'does nothing on an empty stack' do
      expect { stack.draw(renderer, screen_view) }.not_to raise_error
    end
  end

  # A scene is a whole subtree that may contain nodes owned by different
  # players, so what has to reach it is the input *source*, not the one
  # player's snapshot a component is handed. Scenes live off the child list, so
  # the traversal cannot carry it there on its own.
  describe 'routing input into the scene' do
    let(:players) do
      RGame::Engine::Players.new(
        [RGame::Engine::Player.new(id: 0, device: RGame::Util::Controls::KEYBOARD),
         RGame::Engine::Player.new(id: 1, device: RGame::Util::Controls.gamepad(0))]
      )
    end
    let(:stack) { described_class.new }

    let(:scene) do
      Class.new(RGame::Engine::Node2D) do
        attr_reader :seen

        def on_control(actions) = @seen = actions
      end.new
    end

    before do
      backend = FakeInputBackend.new
      backend.hold(RGame::Util::Controls::KEY_SPACE)
      backend.hold(RGame::Util::Controls::PAD_A, device: RGame::Util::Controls.gamepad(0))
      players.poll(backend)
    end

    # A host with the stack mounted and the scene pushed, optionally with the
    # player registry alongside it — the shape RGame::Game builds.
    def mount(registry: players)
      host = RGame::Engine::Node2D.new
      host.add_component(registry) if registry
      host.add_component(stack)
      host.enter_tree
      stack.push(scene)
      host
    end

    it 'passes the registry down, so a scene resolves its own owners' do
      host = mount
      scene.input_owner = players[1]

      host.control(players)

      expect(scene.seen).to equal(players[1].actions)
    end

    it 'gives an unowned scene the primary player' do
      mount.control(players)

      expect(scene.seen).to equal(players[0].actions)
    end

    # Without a registry in the tree there is only one answer anyway, so the
    # snapshot is passed straight on — which is what every spec predating
    # players relies on.
    it 'falls back to the snapshot it was handed when no registry is mounted' do
      snapshot = RGame::Engine::Actions.new(held: { fire: true })

      mount(registry: nil).control(snapshot)

      expect(scene.seen).to equal(snapshot)
    end
  end
end
