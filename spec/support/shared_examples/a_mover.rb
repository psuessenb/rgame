# frozen_string_literal: true

# What every Components::Mover promises about being stopped, stated once and run against
# each of them — CharacterBody, Velocity and PathFollow.
#
# The three compute a step three different ways, and each has its own spec for that. What
# they share is everything after: `blocked_by:` resolved at attach, a step stopped flush,
# and the two edges reported once. A mover that got any of it subtly different would pass
# its own spec and still be the one thing in a scene that walks through a wall, so the
# promise is checked here rather than trusted to the base class.
#
# ## What the host must provide
#
#   it_behaves_like 'a mover' do
#     def build_mover(blocked_by:) = ...
#   end
#
# A mover, unattached, that carries its node **rightwards at 60 px/s from wherever the node
# stands** — (170, 100) — for at least four seconds. The group builds everything else: a
# scene with a real CollisionWorld, a 16x400 `:wall` collider whose left edge is at x = 200,
# and a node with a 16x16 box. At 60 ticks a second that is one pixel a step, and the box
# meets the wall after fourteen.
#
# The names below are prefixed so they cannot shadow, or be shadowed by, the host spec's
# own `node` and `root`.
RSpec.shared_examples 'a mover' do
  def mover_dt = 1.0 / 60

  let(:mover_scene) { RGame::Engine::Node2D.new.tap { it.scene = it } }
  let(:mover_node) { RGame::Engine::Node2D.new(x: 170.0, y: 100.0) }
  let(:wall_node) { RGame::Engine::Node2D.new(x: 200.0, y: 0.0) }
  let(:wall) { RGame::Engine::Components::BoxCollider.new(width: 16, height: 400, layer: :wall) }

  def mount_collision_world
    mover_scene.add_component(RGame::Engine::Components::CollisionWorld.new(cell_size: 64))
  end

  def add_box
    mover_node.add_component(RGame::Engine::Components::BoxCollider.new(width: 16, height: 16, layer: :mover))
  end

  # The node is assembled whole and then brought live, so the mover attaches with its
  # sibling collider already there.
  def enter(mover)
    wall_node.add_component(wall)
    mover_scene.add_node(wall_node)
    mover_node.add_component(mover)
    mover_scene.add_node(mover_node)
    mover_scene.enter_tree
    mover
  end

  # A whole scene tick: the CollisionWorld rebuilds its index, then the nodes move.
  def run_ticks(count) = count.times { mover_scene.update(mover_dt) }

  describe 'declaring nothing' do
    it 'passes through the wall' do
      mount_collision_world
      add_box
      enter(build_mover(blocked_by: []))
      run_ticks(60)
      expect(mover_node.x).to be_within(1e-6).of(230.0)
    end

    it 'needs no collider and no collision system' do
      enter(build_mover(blocked_by: []))
      run_ticks(60)
      expect(mover_node.x).to be_within(1e-6).of(230.0)
    end
  end

  describe 'blocked_by: [:wall]' do
    let!(:mover) do
      mount_collision_world
      add_box
      enter(build_mover(blocked_by: [:wall]))
    end

    it 'stops flush against the wall' do
      run_ticks(60)
      expect(mover_node.x).to eq(184.0) # the box's right edge, 16 px on, rests at 200
    end

    it 'reports on_blocked once, with the wall, however long it presses' do
      stopped_by = []
      mover.on_blocked { stopped_by << it }
      run_ticks(60)
      expect(stopped_by).to eq([wall])
    end

    it 'reports on_unblocked once when the wall leaves' do
      released_from = []
      mover.on_unblocked { released_from << it }
      run_ticks(60)
      wall_node.x = 1000.0
      run_ticks(10)
      expect(released_from).to eq([wall])
    end

    it 'goes on once the wall has left' do
      run_ticks(60)
      wall_node.x = 1000.0
      run_ticks(10)
      expect(mover_node.x).to be > 184.0
    end

    # Pressed into the wall, which is the step that runs the whole resolver: the broadphase
    # query, the snap and the blocker bookkeeping.
    it 'allocates nothing on a blocked step' do
      run_ticks(60)
      expect { mover.update(mover_dt) }.to allocate_nothing
    end
  end

  describe 'what it refuses at attach' do
    it 'refuses a declaration on a node with no BoxCollider' do
      mount_collision_world
      expect { enter(build_mover(blocked_by: [:wall])) }
        .to raise_error(/needs a RGame::Engine::Components::BoxCollider/)
    end

    it 'refuses a collider layer on a scene with no CollisionWorld, naming the mover and the layer' do
      add_box
      mover = build_mover(blocked_by: [:wall])
      name = mover.class.name.split('::').last
      expect { enter(mover) }.to raise_error(/#{name} is blocked_by :wall.*no CollisionWorld/m)
    end
  end
end
