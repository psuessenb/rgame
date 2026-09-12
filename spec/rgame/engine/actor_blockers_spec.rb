# frozen_string_literal: true

RSpec.describe RGame::Engine::ActorBlockers do
  # The source needs no scene: something answering query_box and reindex is the whole of
  # what it asks the world for. The colliders are real, because what separates a box from
  # a circle here is `is_a?` and a verifying double is an instance of neither.
  subject(:blockers) { described_class.new(world: world, owner: owner, layers: %i[npc wall]) }

  let(:world) { instance_double(RGame::Engine::Components::CollisionWorld) }

  # Colliders hang under a root: a parentless node is pinned to the world origin, and
  # aabb_x is world_x + the box offset.
  let(:root) { RGame::Engine::Node2D.new }

  let(:owner) { box_at(0, 0, layer: :hero) }

  def box_at(x, y, layer:, width: 10, height: 10)
    add(RGame::Engine::Components::BoxCollider.new(width: width, height: height, layer: layer), x, y)
  end

  def circle_at(x, y, layer:, radius: 5)
    add(RGame::Engine::Components::CircleCollider.new(radius: radius, layer: layer), x, y)
  end

  def add(component, x, y)
    node = RGame::Engine::Node2D.new(x: x, y: y)
    collider = node.add_component(component)
    root.add_node(node)
    root.enter_tree
    collider
  end

  # What the broadphase offers for any query. The candidates are fixed per example, which
  # is what keeps these about the arithmetic rather than about bucketing.
  def offering(*candidates)
    allow(world).to receive(:query_box) { |_x, _y, _w, _h, &block| candidates.each(&block) }
  end

  # The mover: a 10x10 box at (0, 0) unless an example says otherwise.
  def resolve_x(dx, x: 0.0, y: 0.0) = blockers.resolve_x(x, y, 10.0, 10.0, dx)
  def resolve_y(dy, x: 0.0, y: 0.0) = blockers.resolve_y(x, y, 10.0, 10.0, dy)

  describe 'a step into a collider on a blocked layer' do
    it 'lands flush against its left edge moving right' do
      offering(box_at(20, 0, layer: :npc))
      expect(resolve_x(100.0)).to eq(10.0) # the mover's right edge on the blocker's left
    end

    it 'lands flush against its right edge moving left' do
      offering(box_at(-30, 0, layer: :npc))
      expect(resolve_x(-100.0, x: 0.0)).to eq(-20.0) # the blocker's right edge is -20
    end

    it 'lands flush against its top edge moving down' do
      offering(box_at(0, 20, layer: :npc))
      expect(resolve_y(100.0)).to eq(10.0)
    end

    it 'lands flush against its bottom edge moving up' do
      offering(box_at(0, -30, layer: :npc))
      expect(resolve_y(-100.0)).to eq(-20.0)
    end

    it 'moves freely when nothing is in the way' do
      offering
      expect(resolve_x(4.0)).to eq(4.0)
    end

    # A collider beside the step rather than in it: the far axis has to overlap before the
    # near one can be blocked at all.
    it 'is not stopped by a collider the step passes above' do
      offering(box_at(20, 40, layer: :npc))
      expect(resolve_x(100.0)).to eq(100.0)
    end
  end

  it 'is not stopped by a collider on a layer it did not declare' do
    offering(box_at(20, 0, layer: :pickup))
    expect(resolve_x(100.0)).to eq(100.0)
  end

  # What lets a crowd of NPCs all declare blocked_by: [:npc] — each of them is on that
  # layer itself, and none of them is stopped by standing where it stands.
  it 'is never stopped by the owner, even on a declared layer' do
    own = described_class.new(world: world, owner: owner, layers: %i[hero npc])
    offering(owner)
    expect(own.resolve_x(0.0, 0.0, 10.0, 10.0, 100.0)).to eq(100.0)
  end

  # CollisionWorld#query_box skips these already; this pins that the source does not
  # depend on that, since a candidate list is all it sees.
  it 'is not stopped by a collider whose node is queued for removal' do
    dead = box_at(20, 0, layer: :npc)
    dead.node.queue_free
    offering(dead)
    expect(resolve_x(100.0)).to eq(100.0)
  end

  # Blocking is box-versus-box. A circle on a blocked layer reports on_hit and stops
  # nothing, which is the documented limit rather than an oversight.
  it 'is not stopped by a CircleCollider on a declared layer' do
    offering(circle_at(25, 5, layer: :npc))
    expect(resolve_x(100.0)).to eq(100.0)
  end

  it 'lands against the nearest of several blockers' do
    offering(box_at(60, 0, layer: :npc), box_at(20, 0, layer: :wall), box_at(90, 0, layer: :npc))
    expect(resolve_x(100.0)).to eq(10.0)
  end

  it 'lands against the nearest going the other way too' do
    offering(box_at(-60, 0, layer: :npc), box_at(-30, 0, layer: :wall))
    expect(resolve_x(-100.0)).to eq(-20.0)
  end

  # Blocking stops the mover; it never moves the thing it hit. So a pair that is already
  # interpenetrating is left alone rather than being shoved apart.
  it 'does not resolve an overlap that already exists' do
    offering(box_at(5, 0, layer: :npc))
    expect(resolve_x(4.0)).to eq(4.0)
  end

  # The broadphase offers a collider once per cell the two share, so the same one can
  # arrive twice. The running minimum is what makes that not matter.
  it 'gives the same answer for a collider offered twice' do
    twice = box_at(20, 0, layer: :npc)
    offering(twice, twice)
    expect(resolve_x(100.0)).to eq(10.0)
  end

  describe '#blocker' do
    it 'names the collider that produced the edge' do
      wall = box_at(20, 0, layer: :npc)
      offering(wall)
      resolve_x(100.0)
      expect(blockers.blocker).to be(wall)
    end

    it 'names the nearer one when several were in the way' do
      near = box_at(20, 0, layer: :npc)
      offering(box_at(60, 0, layer: :npc), near)
      resolve_x(100.0)
      expect(blockers.blocker).to be(near)
    end

    it 'is nil when the step was free' do
      offering(box_at(20, 0, layer: :npc))
      resolve_x(100.0)
      offering
      resolve_x(1.0)
      expect(blockers.blocker).to be_nil
    end

    it 'is nil for a zero step' do
      offering(box_at(20, 0, layer: :npc))
      resolve_x(100.0)
      resolve_x(0.0)
      expect(blockers.blocker).to be_nil
    end

    it 'is per axis — resolve_y replaces what resolve_x found' do
      offering(box_at(20, 0, layer: :npc))
      resolve_x(100.0)
      resolve_y(1.0)
      expect(blockers.blocker).to be_nil
    end
  end

  # The mover re-buckets itself once its resolved position is written back, which is what
  # keeps the index exact for whoever resolves next this step.
  it 're-indexes the owner at the box the step started from' do
    allow(world).to receive(:reindex)
    blockers.moved(:actor, 1.0, 2.0, 10.0, 10.0)
    expect(world).to have_received(:reindex).with(owner, 1.0, 2.0, 10.0, 10.0)
  end

  # Per actor per axis per step, so neither the query nor the arithmetic may allocate.
  describe 'allocation' do
    # A plain class rather than the instance double the rest of these use: an RSpec double
    # allocates per call (measurably — 126 objects a step here), which would drown out what
    # this is measuring.
    let(:fixed_world) do
      Class.new do
        def initialize(candidates) = @candidates = candidates
        def query_box(_x, _y, _w, _h, &) = @candidates.each(&)
      end
    end

    it 'allocates nothing resolving a blocked step on either axis' do
      world = fixed_world.new([box_at(20, 0, layer: :npc), box_at(0, 20, layer: :npc)])
      source = described_class.new(world: world, owner: owner, layers: [:npc])
      source.resolve_x(0.0, 0.0, 10.0, 10.0, 100.0) # warm
      expect do
        source.resolve_x(0.0, 0.0, 10.0, 10.0, 100.0)
        source.resolve_y(0.0, 0.0, 10.0, 10.0, 100.0)
      end.to allocate_nothing
    end
  end
end
