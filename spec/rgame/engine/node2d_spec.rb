# frozen_string_literal: true

# require_relative 'fake_renderer'

# Two distinct component types so the class-keyed registry (add/get_component,
# which match on `is_a?`) can be exercised with real classes — doubles have no
# meaningful `.class` to key on.
class SpecHealthComponent < RGame::Engine::Component; end
class SpecPhysicsComponent < RGame::Engine::Component; end

# Records its tree-lifecycle calls into an injected shared log, so the enter/exit
# cascade order (component attach before node on_add, etc.) can be asserted with a
# real component class rather than a stub.
class SpecLifecycleComponent < RGame::Engine::Component
  attr_accessor :log

  def on_attach = log << :component_attach
  def on_detach = log << :component_detach
end

# A node that records its own on_add/on_remove into the same shared log.
class SpecLifecycleNode < RGame::Engine::Node2D
  attr_accessor :log

  def on_add    = log << :node_add
  def on_remove = log << :node_remove
end

# Moves itself in its own update hook, which is what a node with a velocity of
# its own does. Used to check that its subtree follows it within the same tick.
class SpecSelfMovingNode < RGame::Engine::Node2D
  def on_update(_dt) = self.x += 10
end

# Records each lifecycle-hook call (with its argument) to a shared log, so the
# per-phase order (components, then this node's hook, then children) can be
# asserted without stubbing the node under test.
class SpecRecordingNode < RGame::Engine::Node2D
  def initialize(log)
    super()
    @log = log
  end

  def on_control(actions) = @log << [:hook, actions]
  def on_update(dt)       = @log << [:hook, dt]
  def on_draw(renderer, _view) = @log << [:hook, renderer]
end

RSpec.describe RGame::Engine::Node2D do
  subject(:node) { described_class.new }

  describe 'construction' do
    it 'defaults position, size and containers to zero/empty' do
      expect([node.x, node.y, node.z, node.width, node.height]).to eq([0, 0, 0, 0, 0])
      expect(node.children).to eq([])
      expect(node.components).to eq([])
      expect(node.parent).to be_nil
    end

    it 'is its own root and is outside the tree until it enters' do
      expect(node.root).to be(node)
      expect(node.scene).to be_nil
      expect(node).not_to be_in_tree
    end

    it 'takes position and size as keyword args' do
      node = described_class.new(x: 1, y: 2, z: 3, width: 4, height: 5)
      expect([node.x, node.y, node.z, node.width, node.height]).to eq([1, 2, 3, 4, 5])
    end
  end

  describe '#add_node' do
    let(:child) { described_class.new }

    it 'appends the child and returns it' do
      expect(node.add_node(child)).to be(child)
      expect(node.children).to eq([child])
    end

    it 'sets the child parent to this node' do
      node.add_node(child)
      expect(child.parent).to be(node)
    end

    it 'sets the child root to this node when this node is a root' do
      node.add_node(child)
      expect(child.root).to be(node)
    end

    it 'propagates the top-most root to grandchildren' do
      grandchild = described_class.new
      node.add_node(child)
      child.add_node(grandchild)
      expect(grandchild.root).to be(node)
    end

    it 'resolves the top-most node as its own root' do
      node.add_node(child)
      expect(node.root).to be(node)
    end
  end

  describe '#remove_node' do
    let(:child) { described_class.new }

    before { node.add_node(child) }

    it 'detaches the child and returns it' do
      expect(node.remove_node(child)).to be(child)
      expect(node.children).to eq([])
    end

    it 'clears the child parent' do
      node.remove_node(child)
      expect(child.parent).to be_nil
    end

    it 'leaves the detached child as its own root' do
      node.remove_node(child)
      expect(child.root).to be(child)
    end

    it 'leaves siblings attached' do
      sibling = described_class.new
      node.add_node(sibling)
      node.remove_node(child)
      expect(node.children).to eq([sibling])
    end
  end

  describe '#add_component' do
    let(:component) { SpecHealthComponent.new }

    it 'attaches the component and returns it' do
      expect(node.add_component(component)).to be(component)
      expect(node.components).to eq([component])
    end

    it 'back-links the component to the node' do
      node.add_component(component)
      expect(component.node).to be(node)
    end

    it 'rejects a second component of the same class' do
      node.add_component(SpecHealthComponent.new)
      expect { node.add_component(SpecHealthComponent.new) }.to raise_error(ArgumentError)
    end

    it 'allows components of different classes to coexist' do
      health = SpecHealthComponent.new
      physics = SpecPhysicsComponent.new
      node.add_component(health)
      node.add_component(physics)
      expect(node.components).to eq([health, physics])
    end
  end

  describe '#get_component' do
    it 'returns the attached component of that class' do
      component = SpecHealthComponent.new
      node.add_component(component)
      expect(node.get_component(SpecHealthComponent)).to be(component)
    end

    it 'returns nil when no component of that class is attached' do
      expect(node.get_component(SpecHealthComponent)).to be_nil
    end

    it 'matches by ancestry, so a base class finds a subclass instance' do
      component = SpecHealthComponent.new
      node.add_component(component)
      expect(node.get_component(RGame::Engine::Component)).to be(component)
    end
  end

  describe '#remove_component' do
    let(:component) { SpecHealthComponent.new }

    before { node.add_component(component) }

    it 'detaches the component of that class and returns it' do
      expect(node.remove_component(SpecHealthComponent)).to be(component)
      expect(node.components).to eq([])
    end

    it 'unlinks the component from the node' do
      node.remove_component(SpecHealthComponent)
      expect(component.node).to be_nil
    end

    it 'returns nil and leaves components untouched when none of that class is attached' do
      expect(node.remove_component(SpecPhysicsComponent)).to be_nil
      expect(node.components).to eq([component])
    end

    it 'matches by ancestry, so a base class removes a subclass instance' do
      expect(node.remove_component(RGame::Engine::Component)).to be(component)
      expect(node.components).to eq([])
    end

    it 'removes only the matching component, leaving others attached' do
      physics = SpecPhysicsComponent.new
      node.add_component(physics)
      node.remove_component(SpecHealthComponent)
      expect(node.components).to eq([physics])
    end
  end

  describe 'named component slots (as:)' do
    it 'lets two components of the same class coexist under distinct names' do
      spawn = SpecHealthComponent.new
      wave = SpecHealthComponent.new
      node.add_component(spawn, as: :spawn)
      node.add_component(wave, as: :wave)
      expect(node.components).to eq([spawn, wave])
    end

    it 'looks a named component up by its name' do
      spawn = SpecHealthComponent.new
      node.add_component(spawn, as: :spawn)
      expect(node.get_component(:spawn)).to be(spawn)
    end

    it 'returns nil for an unused name' do
      expect(node.get_component(:nope)).to be_nil
    end

    it 'still rejects a second component in the same named slot' do
      node.add_component(SpecHealthComponent.new, as: :spawn)
      expect { node.add_component(SpecPhysicsComponent.new, as: :spawn) }.to raise_error(ArgumentError)
    end

    it 'raises on an ambiguous class lookup when several share a type' do
      node.add_component(SpecHealthComponent.new, as: :spawn)
      node.add_component(SpecHealthComponent.new, as: :wave)
      expect { node.get_component(SpecHealthComponent) }.to raise_error(ArgumentError, /look one up by name/)
    end

    it 'removes a single named component by its name' do
      spawn = SpecHealthComponent.new
      wave = SpecHealthComponent.new
      node.add_component(spawn, as: :spawn)
      node.add_component(wave, as: :wave)
      expect(node.remove_component(:spawn)).to be(spawn)
      expect(node.components).to eq([wave])
    end
  end

  describe 'tree lifecycle' do
    subject(:node) { SpecLifecycleNode.new.tap { it.log = log } }

    let(:log)       { [] }
    let(:component) { SpecLifecycleComponent.new.tap { it.log = log } }

    before { node.add_component(component) }

    describe '#enter_tree' do
      it 'does not fire when a component is merely added outside the tree' do
        expect(log).to eq([])
      end

      it 'attaches components before running the node on_add hook' do
        node.enter_tree
        expect(log).to eq(%i[component_attach node_add])
      end

      it 'marks the node as in the tree' do
        node.enter_tree
        expect(node).to be_in_tree
      end

      it 'enters children that were added before it entered the tree' do
        child = node.add_node(described_class.new)
        expect(child).not_to be_in_tree # deferred while the parent is outside the tree
        node.enter_tree
        expect(child).to be_in_tree
      end

      it 'is idempotent' do
        node.enter_tree
        node.enter_tree
        expect(log).to eq(%i[component_attach node_add])
      end
    end

    describe '#exit_tree' do
      before { node.enter_tree }

      it 'runs the node on_remove hook before detaching components' do
        log.clear
        node.exit_tree
        expect(log).to eq(%i[node_remove component_detach])
      end

      it 'marks the node as out of the tree' do
        node.exit_tree
        expect(node).not_to be_in_tree
      end
    end

    describe '#add_node when already live' do
      before { node.enter_tree }

      it 'enters the child immediately' do
        child = node.add_node(described_class.new)
        expect(child).to be_in_tree
      end
    end

    describe '#remove_node when live' do
      before { node.enter_tree }

      it 'exits the removed child' do
        child = node.add_node(described_class.new)
        node.remove_node(child)
        expect(child).not_to be_in_tree
      end
    end

    describe '#add_component when already live' do
      before { node.enter_tree }

      it 'attaches the late component immediately' do
        log.clear
        late = SpecPhysicsComponent.new
        attached = []
        allow(late).to receive(:on_attach) { attached << late }
        node.add_component(late)
        expect(attached).to eq([late])
      end
    end

    describe '#remove_component when live' do
      before { node.enter_tree }

      it 'detaches the component' do
        node.remove_component(SpecLifecycleComponent)
        expect(log).to eq(%i[component_attach node_add component_detach])
      end
    end
  end

  describe 'anchors and systems' do
    describe '#scene' do
      it 'is nil outside any scene' do
        expect(node.scene).to be_nil
      end

      it 'reports a boundary node (scene = self) as its own scene' do
        node.scene = node
        expect(node.scene).to be(node)
      end

      it 'resolves to the nearest boundary node for descendants' do
        node.scene = node
        child = node.add_node(described_class.new)
        grandchild = child.add_node(described_class.new)
        expect(grandchild.scene).to be(node)
      end
    end

    describe '#system' do
      it 'finds a system component on the scene boundary' do
        node.scene = node
        system = node.add_component(SpecPhysicsComponent.new)
        child = node.add_node(described_class.new)
        expect(child.system(SpecPhysicsComponent)).to be(system)
      end

      it 'falls back to a global system on the root when the scene has none' do
        global = node.add_component(SpecHealthComponent.new)
        scene = node.add_node(described_class.new)
        scene.scene = scene
        child = scene.add_node(described_class.new)
        expect(child.system(SpecHealthComponent)).to be(global)
      end

      it 'prefers the scene-scoped system over a global one of the same class' do
        node.add_component(SpecPhysicsComponent.new) # global
        scene = node.add_node(described_class.new)
        scene.scene = scene
        local = scene.add_component(SpecPhysicsComponent.new)
        child = scene.add_node(described_class.new)
        expect(child.system(SpecPhysicsComponent)).to be(local)
      end
    end
  end

  describe 'deferred free' do
    it 'marks a node freed without detaching it' do
      child = node.add_node(described_class.new)
      child.queue_free
      expect(child).to be_freed
      expect(node.children).to eq([child]) # still attached until the next sweep
    end

    describe '#sweep_freed' do
      before { node.enter_tree }

      it 'detaches freed children and takes them out of the tree' do
        child = node.add_node(described_class.new)
        child.queue_free
        node.sweep_freed
        expect(node.children).to eq([])
        expect(child).not_to be_in_tree
      end

      it 'keeps live children and recurses into them' do
        keep = node.add_node(described_class.new)
        grandchild = keep.add_node(described_class.new)
        grandchild.queue_free
        node.sweep_freed
        expect(node.children).to eq([keep])
        expect(keep.children).to eq([])
      end

      it 'forwards the sweep into its components' do
        component = instance_double(RGame::Engine::Component, :node= => nil, on_attach: nil, sweep_freed: nil)
        node.add_component(component)
        node.sweep_freed
        expect(component).to have_received(:sweep_freed)
      end
    end
  end

  describe 'the tick' do
    subject(:node) { SpecRecordingNode.new(log) }

    let(:log)       { [] }
    let(:component) { instance_double(RGame::Engine::Component) }
    let(:child)     { described_class.new }

    before { allow(component).to receive(:node=) }

    describe '#control' do
      let(:actions) do
        instance_double(RGame::Engine::Actions).tap do |snapshot|
          # A snapshot is its own input source: with one answer for everyone,
          # resolving it returns itself.
          allow(snapshot).to receive(:actions_for).and_return(snapshot)
        end
      end

      it 'drives components, then its own hook, then children — each with the actions' do
        allow(component).to receive(:control) { |a| log << [:component, a] }
        allow(child).to receive(:control) { |a| log << [:child, a] }
        node.add_component(component)
        node.add_node(child)

        node.control(actions)

        expect(log).to eq([[:component, actions], [:hook, actions], [:child, actions]])
      end
    end

    describe '#update' do
      it 'drives components, then its own hook, then children — each with the timestep' do
        allow(component).to receive(:update) { |dt| log << [:component, dt] }
        allow(child).to receive(:update) { |dt| log << [:child, dt] }
        node.add_component(component)
        node.add_node(child)

        node.update(0.016)

        expect(log).to eq([[:component, 0.016], [:hook, 0.016], [:child, 0.016]])
      end
    end

    describe '#draw' do
      # An unrotated node (the root resolves to world_angle 0) draws straight through,
      # without the renderer.rotated wrapper, so a plain double suffices — but
      # every node opens a layer, so that one has to yield.
      let(:renderer) { instance_double(FakeRenderer, layered: nil) }

      before { allow(renderer).to receive(:layered).and_yield }

      it 'draws components, then its own hook, then children — each with the renderer' do
        allow(component).to receive(:draw) { |r, _v| log << [:component, r] }
        allow(child).to receive(:draw) { |r, _v| log << [:child, r] }
        node.add_component(component)
        node.add_node(child)

        node.draw(renderer, screen_view)

        expect(log).to eq([[:component, renderer], [:hook, renderer], [:child, renderer]])
      end
    end
  end

  describe 'absolute position' do
    # Seeded at construction rather than left nil. A node built but not yet
    # driven reads as being at the origin — which is the same answer
    # resolve_origin gives an unparented node, and saves everything that reads
    # abs_* on a draw path from a NoMethodError the first time it runs early.
    it 'reads as the origin before any phase has run' do
      expect([node.world_x, node.world_y]).to eq([0, 0])
    end

    it 'pins a root node to the origin regardless of its own coordinates' do
      node = described_class.new(x: 10, y: 20)
      node.update(0)
      expect([node.world_x, node.world_y]).to eq([0, 0])
    end

    it 'offsets a child from the origin by its own coordinates' do
      child = described_class.new(x: 10, y: 20)
      node.add_node(child)
      node.update(0)
      expect([child.world_x, child.world_y]).to eq([10, 20])
    end

    it 'accumulates coordinates down the tree' do
      mid = described_class.new(x: 10, y: 20)
      leaf = described_class.new(x: 5, y: 6)
      node.add_node(mid)
      mid.add_node(leaf)

      node.update(0)

      expect([leaf.world_x, leaf.world_y]).to eq([15, 26])
    end

    it 'does not resolve z into anything — depth is where the traversal reaches a node' do
      child = described_class.new(z: 3)
      node.add_node(child)
      node.update(0)

      expect(child).not_to respond_to(:abs_z)
      expect(child.z).to eq(3)
    end

    it 're-resolves when a coordinate changes between phases' do
      child = described_class.new(x: 1)
      node.add_node(child)
      node.update(0)
      child.x = 7

      node.update(0)

      expect(child.world_x).to eq(7)
    end

    # Drawing places a node by pushing its transform, not by reading its resolved
    # coordinates — but `draw` resolves them anyway, because culling is world-space
    # and a paused node under a moving ancestor would otherwise cull against a
    # stale box. See Node2D#draw and node2d_paused_spec.rb.
    it 'resolves during draw the same way it does during update' do
      renderer = instance_double(FakeRenderer, layered: nil)
      allow(renderer).to receive(:layered).and_yield
      allow(renderer).to receive(:rotated).and_yield
      allow(renderer).to receive(:translated).and_yield
      child = described_class.new(x: 4, y: 5)
      node.add_node(child)
      node.draw(renderer, screen_view)
      expect([child.world_x, child.world_y]).to eq([4, 5])
    end
  end

  describe 'rotation' do
    # Angles are radians; floating-point trig means resolved coordinates are
    # compared with a tolerance rather than for exact equality.
    let(:tolerance) { 1e-9 }

    it 'defaults the angle to zero' do
      expect(node.angle).to eq(0)
    end

    it 'takes the angle as a keyword arg' do
      expect(described_class.new(angle: 1.5).angle).to eq(1.5)
    end

    it 'reads as unrotated before any phase has run' do
      expect(node.world_angle).to eq(0)
    end

    it 'pins a root node to zero rotation regardless of its own angle' do
      node = described_class.new(angle: 1.0)
      node.update(0)
      expect(node.world_angle).to eq(0)
    end

    it 'accumulates angle down the tree' do
      mid  = described_class.new(angle: 0.5)
      leaf = described_class.new(angle: 0.25)
      node.add_node(mid)
      mid.add_node(leaf)

      node.update(0)

      expect(leaf.world_angle).to be_within(tolerance).of(0.75)
    end

    it 'rotates a child local offset by an ancestor angle' do
      mid  = described_class.new(angle: Math::PI / 2) # quarter turn
      leaf = described_class.new(x: 10)               # 10 along the rotated x-axis
      node.add_node(mid)
      mid.add_node(leaf)

      node.update(0)

      # A quarter turn maps local +x onto +y: (10, 0) -> (0, 10).
      expect(leaf.world_x).to be_within(tolerance).of(0)
      expect(leaf.world_y).to be_within(tolerance).of(10)
    end

    it 'composes rotation with the rotating ancestor own offset' do
      mid  = described_class.new(x: 5, angle: Math::PI / 2)
      leaf = described_class.new(x: 10)
      node.add_node(mid)
      mid.add_node(leaf)

      node.update(0)

      # leaf offset (10, 0) rotated a quarter turn -> (0, 10), added to mid at (5, 0).
      expect(leaf.world_x).to be_within(tolerance).of(5)
      expect(leaf.world_y).to be_within(tolerance).of(10)
    end

    it 'keeps a child unrotated and at its plain offset when no ancestor rotates' do
      child = described_class.new(x: 10, y: 20)
      node.add_node(child)
      node.update(0)
      expect([child.world_x, child.world_y, child.world_angle]).to eq([10, 20, 0])
    end
  end

  # Every other tree in this file sits at the origin, unrotated, and
  # #resolve_origin has a fast path for exactly that case (`pa.zero?` -> plain
  # addition, no trig). So an unrotated tree cannot tell a correct
  # implementation from several wrong ones: the sin/cos terms all vanish, and a
  # transform that mixes up the axes, applies the rotation on the wrong side, or
  # updates one axis without the other passes just as happily.
  #
  # This is the shape that can tell them apart. The expectations are stated as
  # plain geometry rather than re-derived from the implementation's formula: a
  # quarter turn maps the parent's local +x onto world +y and its local +y onto
  # world -x, so a child walking right in its parent's frame walks *down* the
  # screen, offset from wherever the parent itself sits.
  describe 'a child under a rotated, offset parent' do
    subject(:root) { described_class.new }

    let(:tolerance) { 1e-9 }
    let(:quarter) { Math::PI / 2 }
    # Deliberately offset *and* rotated: an implementation that drops the
    # translation still passes a rotation-only test, and vice versa.
    let(:parent) { described_class.new(x: 100, y: 40, angle: quarter) }

    def place(child_x, child_y)
      child = described_class.new(x: child_x, y: child_y)
      root.add_node(parent)
      parent.add_node(child)
      root.update(0)
      child
    end

    it 'maps the child local +x onto world +y, offset by the parent origin' do
      child = place(10, 0)
      expect(child.world_x).to be_within(tolerance).of(100)
      expect(child.world_y).to be_within(tolerance).of(50)
    end

    it 'maps the child local +y onto world -x, offset by the parent origin' do
      child = place(0, 20)
      expect(child.world_x).to be_within(tolerance).of(80)
      expect(child.world_y).to be_within(tolerance).of(40)
    end

    # The one an axis-at-a-time implementation fails: both components of the
    # child's offset contribute to both components of its world position.
    it 'couples the axes when the child is offset on both at once' do
      child = place(10, 20)
      expect(child.world_x).to be_within(tolerance).of(80)
      expect(child.world_y).to be_within(tolerance).of(50)
    end

    it 'gives the child the parent accumulated angle' do
      expect(place(10, 20).world_angle).to be_within(tolerance).of(quarter)
    end

    # Movement, not just placement: the child steps through its parent's frame
    # over several ticks and must stay on the rotated axis the whole way.
    it 'tracks a child stepping along the parent local +x across several ticks' do
      child = place(0, 0)

      walked = Array.new(3) do
        child.x += 10
        root.update(0.016)
        [child.world_x, child.world_y]
      end

      expect(walked[0][0]).to be_within(tolerance).of(100)
      expect(walked[0][1]).to be_within(tolerance).of(50)
      expect(walked[1][1]).to be_within(tolerance).of(60)
      expect(walked[2][1]).to be_within(tolerance).of(70)
      # ...and never drifts off the parent's rotated axis.
      expect(walked.map(&:first)).to all(be_within(tolerance).of(100))
    end

    # A rotation the fast path cannot reach and neither can a sign error: at a
    # half turn both axes invert, which distinguishes R from its transpose.
    it 'inverts both axes under a half turn' do
      parent.angle = Math::PI
      child = place(10, 20)
      expect(child.world_x).to be_within(tolerance).of(90)
      expect(child.world_y).to be_within(tolerance).of(20)
    end

    it 'follows the parent when the parent itself rotates between ticks' do
      child = place(10, 0)
      expect(child.world_y).to be_within(tolerance).of(50)

      parent.angle = 0 # unrotate: local +x is world +x again
      root.update(0.016)

      expect(child.world_x).to be_within(tolerance).of(110)
      expect(child.world_y).to be_within(tolerance).of(40)
    end
  end

  # A node that moves itself is at its new position immediately, not at the next
  # phase. The traversal resolves a node's transform once, at the top of its own
  # update, and then runs the hooks that may move it — so anything reading the
  # resolved position afterwards, its own children included, used to see where
  # the node was before it moved and caught up a tick later.
  describe 'moving a node during a phase' do
    subject(:root) { described_class.new }

    it 'reads back the new resolved position inside the hook that moved it' do
      seen = []
      mover = Class.new(described_class) do
        define_method(:on_update) do |_dt|
          self.x = 10
          seen << world_x
        end
      end
      root.add_node(mover.new)

      root.update(0.016)

      expect(seen).to eq([10])
    end

    it 'carries the subtree along in the same tick rather than the next one' do
      mover = root.add_node(SpecSelfMovingNode.new)
      child = mover.add_node(described_class.new(x: 5))

      followed = Array.new(3) do
        root.update(0.016)
        child.world_x
      end

      # The child sits 5 to the right of a parent that steps 10 per tick, so it
      # is at 15, 25, 35 — not 5, 15, 25 a tick behind.
      expect(followed).to eq([15, 25, 35])
    end

    it 'carries a rotation the same way' do
      mover = root.add_node(described_class.new)
      child = mover.add_node(described_class.new(x: 10))
      root.update(0.016)

      mover.angle = Math::PI / 2
      child.parent.update(0.016) # the subtree, without re-resolving from the root

      expect(child.world_x).to be_within(1e-9).of(0)
      expect(child.world_y).to be_within(1e-9).of(10)
    end
  end

  # A node is *placed* by pushing its transform onto the renderer, not by
  # resolving coordinates and drawing at them. So these examples are about which
  # calls the traversal issues and what is nested inside what.
  describe 'drawing in local space' do
    let(:renderer) { instance_double(FakeRenderer, layered: nil) }

    before do
      allow(renderer).to receive(:layered).and_yield
      allow(renderer).to receive(:translated).and_yield
      allow(renderer).to receive(:rotated).and_yield
    end

    it 'pushes nothing for a node sitting at its parent origin' do
      node.add_node(described_class.new)
      node.draw(renderer, screen_view)
      expect(renderer).not_to have_received(:translated)
    end

    it 'pushes nothing for a root, which is pinned to the identity' do
      root = described_class.new(x: 10, y: 20, angle: 1.0)
      root.draw(renderer, screen_view)
      expect(renderer).not_to have_received(:translated)
      expect(renderer).not_to have_received(:rotated)
    end

    it 'translates by the node parent-relative offset, not its resolved one' do
      mid = node.add_node(described_class.new(x: 10, y: 20))
      mid.add_node(described_class.new(x: 3, y: 4))

      node.draw(renderer, screen_view)

      # The child's own push is (3, 4) — its offset from `mid`. The renderer
      # composes it with mid's (10, 20); nobody hands it the sum.
      expect(renderer).to have_received(:translated).with(10, 20)
      expect(renderer).to have_received(:translated).with(3, 4)
    end

    it 'skips the rotation wrapper for an unrotated node' do
      node.add_node(described_class.new(x: 10))
      node.draw(renderer, screen_view)
      expect(renderer).not_to have_received(:rotated)
    end

    it 'rotates by the node own angle in degrees, about its own origin' do
      node.add_node(described_class.new(x: 10, y: 20, angle: Math::PI / 2))

      node.draw(renderer, screen_view)

      # Quarter turn -> 90 degrees. The pivot is (0, 0) because the translate
      # above it has already put the renderer on the node.
      expect(renderer).to have_received(:rotated).with(a_value_within(1e-9).of(90.0), 0, 0)
    end

    it 'nests both a node own visuals and its children inside its transform' do
      # The reverse of what it used to be. Children no longer carry the parent's
      # rotation in resolved coordinates of their own, so the parent's transform
      # is the only thing placing them and they have to draw underneath it.
      events = []
      allow(renderer).to receive(:translated) do |_dx, _dy, &block|
        events << :translate_begin
        block.call
        events << :translate_end
      end

      mid = SpecRecordingNode.new(events) # logs [:hook, renderer] from on_draw
      mid.x = 10
      child = instance_double(described_class, :parent= => nil, :sibling_order= => nil)
      allow(child).to receive(:draw) { events << :child }
      node.add_node(mid)
      mid.add_node(child)

      node.draw(renderer, screen_view)

      expect(events).to eq([:translate_begin, [:hook, renderer], :child, :translate_end])
    end

    it 'draws a node own visuals before its children, as it always did' do
      events = []
      mid = SpecRecordingNode.new(events)
      child = instance_double(described_class, :parent= => nil, :sibling_order= => nil)
      allow(child).to receive(:draw) { events << :child }
      node.add_node(mid)
      mid.add_node(child)

      node.draw(renderer, screen_view)

      expect(events).to eq([[:hook, renderer], :child])
    end
  end
end
