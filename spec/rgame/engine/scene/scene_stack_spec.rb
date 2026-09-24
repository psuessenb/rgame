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
                                           :scene= => nil, sweep_freed: nil)
  end

  # A switch lands in the sweep, as RGame::Game runs it after each tick.
  def sweep = host.sweep_freed

  def push(scene)
    stack.push(scene)
    sweep
  end

  describe '#current' do
    it 'is nil while the stack is empty' do
      expect(stack.current).to be_nil
    end

    it 'is the most recently pushed scene' do
      first  = scene_double
      second = scene_double
      push(first)
      push(second)
      expect(stack.current).to be(second)
    end
  end

  describe '#push' do
    let(:scene) { scene_double }

    it 'returns the stack for chaining' do
      expect(stack.push(scene)).to be(stack)
    end

    it 'makes the scene current' do
      push(scene)
      expect(stack.current).to be(scene)
    end

    it 'brings the scene into the tree' do
      push(scene)
      expect(scene).to have_received(:enter_tree)
    end

    it 'wires the scene under the host node and marks it as its own scene boundary' do
      push(scene)
      expect(scene).to have_received(:parent=).with(host)
      expect(scene).to have_received(:scene=).with(scene)
    end

    it 'keeps the previous scene underneath' do
      first = scene_double
      push(first)
      push(scene)
      stack.pop
      sweep
      expect(stack.current).to be(first)
    end

    it 'refuses what is neither a node nor a name' do
      expect { stack.push('title') }.to raise_error(TypeError, /node or a name/)
    end

    it 'refuses keywords beside a node' do
      expect { stack.push(scene, score: 1) }.to raise_error(ArgumentError, /score/)
    end
  end

  describe '#pop' do
    it 'returns the stack for chaining' do
      push(scene_double)
      expect(stack.pop).to be(stack)
    end

    it 'removes the current scene' do
      scene = scene_double
      push(scene)
      stack.pop
      sweep
      expect(stack.current).to be_nil
    end

    it 'takes the popped scene out of the tree' do
      scene = scene_double
      push(scene)
      stack.pop
      sweep
      expect(scene).to have_received(:exit_tree)
    end

    it 'detaches the popped scene from the tree' do
      scene = scene_double
      push(scene)
      stack.pop
      sweep
      expect(scene).to have_received(:parent=).with(nil)
      expect(scene).to have_received(:scene=).with(nil)
    end

    it 'is a no-op on an empty stack' do
      expect(stack.pop).to be(stack)
      sweep
      expect(stack.current).to be_nil
    end
  end

  # A scene is held off its host's child list, so it follows the host only
  # because setting `parent` registers it with the host.
  # The same holding, for entering and leaving the tree: the scenes on a stack
  # are in the tree exactly while their host is.
  describe 'a host entering and leaving the tree' do
    let(:root) { RGame::Engine::Node2D.new.tap { it.add_node(host) } }

    it 'keeps a scene pushed while the host is outside the tree out of it' do
      scene = RGame::Engine::Node2D.new
      push(scene)
      expect(scene).not_to be_in_tree
    end

    it 'enters that scene with its host' do
      scene = RGame::Engine::Node2D.new
      push(scene)
      root.enter_tree
      expect(scene).to be_in_tree
    end

    it 'takes every scene on the stack out of the tree with its host' do
      scenes = Array.new(2) { RGame::Engine::Node2D.new }
      root.enter_tree
      scenes.each { push(it) }
      root.remove_node(host)
      expect(scenes.map(&:in_tree?)).to eq([false, false])
    end

    it 'detaches a scene\'s components as the host leaves' do
      detached = []
      component = Class.new(RGame::Engine::Component) { define_method(:_detach) { detached << :detached } }
      scene = RGame::Engine::Node2D.new
      scene.add_component(component.new)
      root.enter_tree
      push(scene)
      root.remove_node(host)
      expect(detached).to eq([:detached])
    end

    it 'brings every scene back with its host' do
      scenes = Array.new(2) { RGame::Engine::Node2D.new }
      root.enter_tree
      scenes.each { push(it) }
      root.remove_node(host)
      root.add_node(host)
      expect(scenes.map(&:in_tree?)).to eq([true, true])
    end
  end

  describe 'a host that moves' do
    # A node with no parent is the root and stays at the origin, so the host
    # needs one to move at all.
    it 'moves the scene with it' do
      RGame::Engine::Node2D.new.add_node(host)
      scene = RGame::Engine::Node2D.new(x: 5)
      push(scene)
      scene.world_x
      host.x = 50
      expect(scene.world_x).to eq(55)
    end

    it 'lets go of the scenes it popped' do
      popped = Class.new(RGame::Engine::Node2D)
      build_in_finished_thread do
        20.times do
          push(popped.new)
          stack.pop
          sweep
        end
      end
      collect_garbage
      expect(ObjectSpace.each_object(popped).count).to eq(0)
    end
  end

  describe '#replace' do
    let(:outgoing) { scene_double }
    let(:incoming) { scene_double }

    before { push(outgoing) }

    it 'makes the new scene current' do
      stack.replace(incoming)
      sweep
      expect(stack.current).to be(incoming)
    end

    it 'removes the outgoing scene' do
      stack.replace(incoming)
      sweep
      expect(outgoing).to have_received(:exit_tree)
    end

    it 'adds the incoming scene' do
      stack.replace(incoming)
      sweep
      expect(incoming).to have_received(:enter_tree)
    end

    it 'does not leave the outgoing scene underneath' do
      stack.replace(incoming)
      sweep
      stack.pop
      sweep
      expect(stack.current).to be_nil
    end

    it 'still pushes when the stack is empty' do
      empty = RGame::Engine::Node2D.new.add_component(described_class.new)
      empty.replace(incoming)
      empty.node.sweep_freed
      expect(empty.current).to be(incoming)
    end
  end

  # Rule 1: a switch lands in the sweep after the tick that asked for it,
  # whoever asked, and `current` changes then.
  describe 'when a switch lands' do
    let(:root) { RGame::Engine::Node2D.new.tap { it.add_node(host) } }
    let(:asker) do
      Class.new(RGame::Engine::Node2D) do
        attr_accessor :during_control, :during_update

        def _control(_actions) = during_control&.call
        def _update(_dt) = during_update&.call
      end
    end
    let(:first) { asker.new }
    let(:second) { RGame::Engine::Node2D.new }

    before do
      root.enter_tree
      push(first)
    end

    def tick
      root.control(RGame::Engine::Actions.new)
      root.update(1.0 / 60)
      root.sweep_freed
    end

    it 'does not change current when asked' do
      stack.replace(second)
      expect(stack.current).to be(first)
      expect(stack).to be_pending
    end

    it 'lands a switch asked for during control in that tick\'s sweep, after update' do
      updated = []
      first.during_control = -> { stack.replace(second) }
      first.during_update = -> { updated << stack.current }
      tick
      expect(updated).to eq([first])
      expect(stack.current).to be(second)
      expect(stack).not_to be_pending
    end

    it 'lands a switch asked for during update in that tick\'s sweep' do
      first.during_update = -> { stack.replace(second) }
      tick
      expect(stack.current).to be(second)
    end

    it 'lands a switch asked for outside a tick in the first sweep' do
      stack.push(second)
      sweep
      expect(stack.current).to be(second)
    end

    it 'sweeps the scene it leaves before the switch lands' do
      leaf = first.add_node(RGame::Engine::Node2D.new)
      leaf.queue_free
      stack.replace(second)
      sweep
      expect(first.children).to be_empty
    end
  end

  # Rule 2.
  describe 'two switches asked for before a sweep' do
    it 'keeps only the last' do
      pushed = scene_double
      replaced = scene_double
      push(scene_double)
      stack.push(pushed)
      stack.replace(replaced)
      sweep
      expect(pushed).not_to have_received(:enter_tree)
      stack.pop
      sweep
      expect(stack.current).to be_nil
    end

    it 'lets a pop cancel a push' do
      below = scene_double
      push(below)
      stack.push(scene_double)
      stack.pop
      sweep
      expect(stack.current).to be_nil
    end
  end

  # Rules 3 and 4.
  describe 'a scene given a name' do
    let(:built) { [] }

    before do
      stack.define(:title) { RGame::Engine::Node2D.new.tap { built << it } }
      stack.define(:game_over) { |score:, best: 0| RGame::Engine::Node2D.new(x: score, y: best) }
      stack.define(:any) { |**keywords| RGame::Engine::Node2D.new(x: keywords.size) }
    end

    it 'is built when the switch lands, not when it is asked for' do
      stack.push(:title)
      expect(built).to be_empty
      sweep
      expect(stack.current).to be(built.first)
    end

    it 'is built again for each switch to it' do
      push(:title)
      push(:title)
      expect(built.uniq.size).to eq(2)
    end

    it 'hands the switch\'s keywords to the builder' do
      stack.replace(:game_over, score: 12, best: 30)
      sweep
      expect([stack.current.x, stack.current.y]).to eq([12, 30])
    end

    it 'leaves an optional keyword to the builder' do
      stack.replace(:game_over, score: 3)
      sweep
      expect(stack.current.y).to eq(0)
    end

    it 'takes any keyword for a builder that takes them all' do
      stack.push(:any, a: 1, b: 2)
      sweep
      expect(stack.current.x).to eq(2)
    end

    it 'raises KeyError for a name it was not given, when asked' do
      expect { stack.push(:village) }.to raise_error(KeyError, /no scene named :village/)
      expect(stack).not_to be_pending
    end

    it 'raises when a required keyword is missing, when asked' do
      expect { stack.replace(:game_over) }.to raise_error(ArgumentError, /needs score/)
    end

    it 'raises for a keyword the builder does not take, when asked' do
      expect { stack.push(:title, score: 1) }.to raise_error(ArgumentError, /takes no score/)
    end

    it 'refuses a name defined twice' do
      expect { stack.define(:title) { RGame::Engine::Node2D.new } }.to raise_error(ArgumentError, /already/)
    end

    it 'refuses a name that is not a Symbol' do
      expect { stack.define('town') { RGame::Engine::Node2D.new } }.to raise_error(TypeError)
    end

    it 'refuses a name with no builder' do
      expect { stack.define(:town) }.to raise_error(ArgumentError, /block/)
    end

    it 'refuses a builder that declares carry or transition' do
      expect { stack.define(:town) { |carry:| carry } }.to raise_error(ArgumentError, /carry/)
      expect { stack.define(:inn) { |transition: nil| transition } }.to raise_error(ArgumentError, /transition/)
    end

    it 'refuses a builder that takes positional parameters' do
      expect { stack.define(:town) { |hero| hero } }.to raise_error(ArgumentError, /keywords only/)
    end
  end

  # Rule 5.
  describe 'carry:' do
    let(:root) { RGame::Engine::Node2D.new.tap { it.add_node(host) } }
    let(:hero) do
      Class.new(RGame::Engine::Node2D) do
        attr_accessor :while_leaving

        def _exit_tree = while_leaving&.call
      end.new
    end
    let(:first) { RGame::Engine::Node2D.new.tap { it.add_node(hero) } }

    before do
      stack.define(:next) do |hero:, entrance: :gate|
        RGame::Engine::Node2D.new(y: entrance == :gate ? 1 : 2).tap { it.add_node(hero) }
      end
      root.enter_tree
      push(first)
    end

    it 'leaves the node where it is until the switch lands' do
      stack.replace(:next, carry: { hero: hero })
      expect(hero.parent).to be(first)
    end

    it 'hands the node to the builder under its key' do
      stack.replace(:next, carry: { hero: hero })
      sweep
      expect(hero.parent).to be(stack.current)
      expect(hero).to be_in_tree
    end

    it 'takes the node from its parent before the old scene leaves the tree' do
      seen = []
      hero.while_leaving = -> { seen << first.in_tree? }
      stack.replace(:next, carry: { hero: hero })
      sweep
      expect(seen).to eq([true])
      expect(first.children).to be_empty
    end

    it 'passes keywords beside it' do
      stack.replace(:next, entrance: :south, carry: { hero: hero })
      sweep
      expect(stack.current.y).to eq(2)
    end

    it 'takes the node out of a scene left underneath, on a push' do
      stack.push(:next, carry: { hero: hero })
      sweep
      expect(first.children).to be_empty
      expect(stack.current.children).to eq([hero])
    end

    it 'refuses carry: beside a node' do
      expect { stack.push(RGame::Engine::Node2D.new, carry: { hero: hero }) }.to raise_error(ArgumentError, /carry/)
    end

    it 'refuses anything but a Hash of names to nodes' do
      expect { stack.replace(:next, carry: [hero]) }.to raise_error(TypeError, /Hash/)
      expect { stack.replace(:next, carry: { hero: :hero }) }.to raise_error(TypeError, /Hash/)
    end

    it 'refuses a key the builder does not take' do
      expect { stack.replace(:next, carry: { hero: hero, pet: hero }) }.to raise_error(ArgumentError, /takes no pet/)
    end

    it 'refuses a key given as a keyword too' do
      expect { stack.replace(:next, hero: hero, carry: { hero: hero }) }.to raise_error(ArgumentError, /both/)
    end
  end

  # The caller that uses both: a hero carried from one room to another, each
  # with a TileWorld and a CollisionWorld of its own. It must leave the first
  # room's index, join the second's, and be stopped by the second map.
  describe 'a hero carried between two rooms' do
    let(:root) { RGame::Engine::Node2D.new.tap { it.add_node(host) } }
    let(:room) do
      Class.new(RGame::Engine::Node2D) do
        def initialize(rows:, hero: nil)
          super()
          components = RGame::Engine::Components
          add_component(components::TileWorld.new(map: WalledTileMap.build(rows), tilemap_id: :level))
          add_component(components::CollisionWorld.new(cell_size: 64))
          add_node(hero) if hero
        end

        def world = get_component(RGame::Engine::Components::CollisionWorld)
      end
    end
    let(:hero) do
      components = RGame::Engine::Components
      RGame::Engine::Node2D.new(x: 256.0, y: 100.0).tap do |node|
        node.add_component(components::BoxCollider.new(width: 16, height: 16, layer: :hero))
        node.add_component(components::CharacterBody.new(speed: 60.0, blocked_by: [:tiles])).set_intent(1, 0)
      end
    end

    def tick(count) = count.times { root.update(1.0 / 60) && sweep }

    def colliders_in(scene)
      found = []
      scene.world.query_box(0, 0, 320, 192) { found << it }
      found.uniq
    end

    before do
      open_rows = Array.new(12) { '.' * 20 }
      walled_rows = Array.new(12) { "#{'.' * 18}#." }
      stack.define(:walled) { |hero:| room.new(rows: walled_rows, hero:) }
      root.enter_tree
      push(room.new(rows: open_rows).tap { it.add_node(hero) })
    end

    it 'leaves the first room\'s index and joins the second\'s' do
      first = stack.current
      collider = hero.get_component(RGame::Engine::Components::BoxCollider)
      allow(first.world).to receive(:unregister).and_call_original
      stack.replace(:walled, carry: { hero: hero })
      sweep
      tick(1)
      expect(first.world).to have_received(:unregister).with(collider)
      expect(colliders_in(stack.current)).to eq([collider])
    end

    it 'is stopped by the second room\'s map' do
      stack.replace(:walled, carry: { hero: hero })
      sweep
      tick(40)
      expect(hero.x).to eq(272.0)
    end
  end

  # Rule 6.
  describe '#on_changed' do
    let(:root) { RGame::Engine::Node2D.new.tap { it.add_node(host) } }
    let(:seen) { [] }

    before do
      root.enter_tree
      stack.on_changed { |scene| seen << [scene, scene&.in_tree?] }
    end

    it 'fires once per switch that lands, with the new top scene in the tree' do
      first = RGame::Engine::Node2D.new
      second = RGame::Engine::Node2D.new
      push(first)
      stack.replace(second)
      sweep
      expect(seen).to eq([[first, true], [second, true]])
    end

    it 'fires with the scene underneath after a pop, and nil once the stack is empty' do
      below = RGame::Engine::Node2D.new
      push(below)
      push(RGame::Engine::Node2D.new)
      seen.clear
      stack.pop
      sweep
      stack.pop
      sweep
      expect(seen).to eq([[below, true], [nil, nil]])
    end

    it 'fires once for two switches asked for before one sweep' do
      stack.push(RGame::Engine::Node2D.new)
      stack.push(RGame::Engine::Node2D.new)
      sweep
      expect(seen.size).to eq(1)
    end

    it 'does not fire for a pop that lands on an empty stack, or a sweep with nothing asked' do
      stack.pop
      sweep
      sweep
      expect(seen).to be_empty
    end
  end

  describe '#control' do
    let(:actions) { instance_double(RGame::Engine::Actions) }

    it 'forwards to the current scene only' do
      below   = scene_double
      current = scene_double
      allow(below).to receive(:control)
      allow(current).to receive(:control)
      push(below)
      push(current)

      stack._control(actions)

      expect(current).to have_received(:control).with(actions)
      expect(below).not_to have_received(:control)
    end

    it 'does nothing on an empty stack' do
      expect { stack._control(actions) }.not_to raise_error
    end
  end

  describe '#update' do
    it 'forwards to the current scene only' do
      below   = scene_double
      current = scene_double
      allow(below).to receive(:update)
      allow(current).to receive(:update)
      push(below)
      push(current)

      stack._update(0.016)

      expect(current).to have_received(:update).with(0.016)
      expect(below).not_to have_received(:update)
    end

    it 'does nothing on an empty stack' do
      expect { stack._update(0.016) }.not_to raise_error
    end
  end

  describe '#sweep_freed' do
    it 'forwards the deferred-free sweep into the current scene' do
      scene = scene_double
      push(scene)
      stack._sweep_freed
      expect(scene).to have_received(:sweep_freed)
    end

    it 'does nothing on an empty stack' do
      expect { stack._sweep_freed }.not_to raise_error
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
      push(below)
      push(current)

      stack._draw(renderer, screen_view)

      expect(drawn).to eq(%i[below current])
    end

    it 'passes the renderer and the view to each scene' do
      scene = scene_double
      view = screen_view
      allow(scene).to receive(:draw)
      push(scene)

      stack._draw(renderer, view)

      expect(scene).to have_received(:draw).with(renderer, view)
    end

    it 'does nothing on an empty stack' do
      expect { stack._draw(renderer, screen_view) }.not_to raise_error
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

        def _control(actions) = @seen = actions
      end.new
    end

    before do
      backend = FakeInputBackend.new
      backend.hold(RGame::Util::Controls::KEY_SPACE)
      backend.hold(RGame::Util::Controls::PAD_A, device: RGame::Util::Controls.gamepad(0))
      players.poll(backend, 0.016)
    end

    # A host with the stack mounted and the scene pushed, optionally with the
    # player registry alongside it — the shape RGame::Game builds.
    def mount(registry: players)
      host = RGame::Engine::Node2D.new
      host.add_component(registry) if registry
      host.add_component(stack)
      host.enter_tree
      stack.push(scene)
      host.sweep_freed
      host
    end

    it 'passes the registry down, so a scene resolves its own owners' do
      host = mount
      scene.input_owner = players[1]

      host.control(players)

      expect(scene.seen.actions_for(nil)).to equal(players[1].actions)
    end

    it 'gives an unowned scene the primary player' do
      mount.control(players)

      expect(scene.seen.actions_for(nil)).to equal(players[0].actions)
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
