# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::CollisionWorld do
  # The world is a system on the scene node; colliders on child nodes register with
  # it through their tree lifecycle. Place colliders, resolve positions with a
  # phase, then tick the world and inspect the hits each collider was told about.
  let(:scene) { RGame::Engine::Node2D.new.tap { it.scene = it } }
  let(:hits)  { [] }

  let!(:world) { scene.add_component(described_class.new(cell_size: 64)) }

  before { scene.enter_tree }

  def place(x, y, layer)
    register(x, y, layer, RGame::Engine::Components::CircleCollider.new(radius: 12, layer: layer))
  end

  # A box collider of the given size, anchored at the node's origin. The world is
  # shape-agnostic, so these register and collide exactly as the circles above do.
  def place_box(x, y, layer, width: 24, height: 24)
    component = RGame::Engine::Components::BoxCollider.new(width: width, height: height, layer: layer)
    register(x, y, layer, component)
  end

  def register(x, y, layer, component)
    node = RGame::Engine::Node2D.new(x: x, y: y)
    collider = node.add_component(component)
    collider.on_hit { |other| hits << [layer, other.layer] }
    scene.add_node(node) # scene is live, so on_attach registers the collider
    collider
  end

  # Resolve the collider nodes' world positions without running the scene's own
  # components -- the world is one of those, and driving it is the next line's
  # job. Only `update` resolves the transform: `control` reads no coordinates and
  # `draw` expresses position by pushing a transform instead of resolving one.
  def resolve_positions = scene.children.each { it.update(0.0) }

  def tick
    resolve_positions
    world.update(0.0)
  end

  describe '#update' do
    it 'reports an overlapping pair to both colliders' do
      place(100, 100, :bullet)
      place(108, 100, :rock)
      tick
      expect(hits).to contain_exactly(%i[bullet rock], %i[rock bullet])
    end

    it 'does not report colliders that are far apart' do
      place(100, 100, :bullet)
      place(400, 400, :rock)
      tick
      expect(hits).to be_empty
    end

    it 'skips colliders whose node is queued for removal' do
      place(100, 100, :bullet)
      place(108, 100, :rock).node.queue_free
      tick
      expect(hits).to be_empty
    end

    it 'reports an overlapping pair of boxes' do
      place_box(100, 100, :snake)
      place_box(110, 110, :fruit)
      tick
      expect(hits).to contain_exactly(%i[snake fruit], %i[fruit snake])
    end

    # The bug this convention exists for: pieces on neighbouring squares border each
    # other constantly, and an inclusive edge test reported every one of those as a
    # contact — a fruit collected by passing the square next to it.
    it 'does not report cell-sized boxes on neighbouring squares' do
      place_box(64, 64, :snake, width: 64, height: 64)
      place_box(128, 64, :fruit, width: 64, height: 64) # shares an edge
      tick
      expect(hits).to be_empty
    end

    it 'reports cell-sized boxes on the same square exactly once each' do
      place_box(64, 64, :snake, width: 64, height: 64)
      place_box(64, 64, :fruit, width: 64, height: 64)
      tick
      expect(hits).to contain_exactly(%i[snake fruit], %i[fruit snake])
    end

    it 'does not report boxes that only overlap on one axis' do
      place_box(100, 100, :snake)
      place_box(110, 200, :fruit)
      tick
      expect(hits).to be_empty
    end

    # Shapes mix: the pair's narrowphase is settled by the two colliders between
    # themselves, so a circle and a box in the same world collide with each other.
    it 'reports a box overlapping a circle' do
      place_box(100, 100, :fruit)   # 24x24 from (100, 100)
      place(130, 112, :bullet)      # radius 12, centre 6px right of the box edge
      tick
      expect(hits).to contain_exactly(%i[fruit bullet], %i[bullet fruit])
    end

    it 'does not report a circle that clears the box' do
      place_box(100, 100, :fruit)
      place(200, 112, :bullet)
      tick
      expect(hits).to be_empty
    end

    # Every collider's broadphase runs per frame, so a box's bucketing and narrowphase
    # must be as allocation-free as a circle's (CLAUDE.md: never allocate on the
    # per-frame path). The colliders share a hash cell without touching, so the pair
    # reaches the narrowphase and is rejected there — a *hit* would allocate in this
    # spec's own on_hit listener, which appends an Array, and measure nothing about
    # the world.
    it 'allocates nothing per step' do
      place_box(70, 70, :snake, width: 10, height: 10)
      place_box(100, 100, :fruit, width: 10, height: 10)
      place(110, 70, :rock)
      tick
      expect { world.update(0.0) }.to allocate_nothing
    end
  end

  describe '#unregister' do
    it 'stops a collider from being reported' do
      place(100, 100, :bullet)
      world.unregister(place(108, 100, :rock))
      tick
      expect(hits).to be_empty
    end
  end

  # query_circle / nearest read the index #update builds, so populate it with a tick
  # before querying. Distances are centre-to-centre (the collider radii don't widen it).
  describe '#query_circle' do
    def in_circle(x, y, r)
      found = []
      world.query_circle(x, y, r) { |collider| found << collider }
      found
    end

    it 'yields colliders whose centre is within the radius' do
      near = place(100, 100, :enemy)
      place(400, 400, :enemy) # outside
      tick
      expect(in_circle(100, 100, 50)).to eq([near])
    end

    it 'excludes a collider just beyond the radius' do
      place(100, 100, :enemy) # 30px away from the query point below
      tick
      expect(in_circle(130, 100, 20)).to be_empty
    end

    it 'skips a collider whose node is queued for removal' do
      place(100, 100, :enemy).node.queue_free
      tick
      expect(in_circle(100, 100, 50)).to be_empty
    end

    it 'yields nothing before the first update has built the index' do
      place(100, 100, :enemy)
      resolve_positions # the world itself is deliberately not driven
      expect(in_circle(100, 100, 50)).to be_empty
    end
  end

  # cell_empty? reads the index #update builds, like the queries above, and asks about
  # world coordinates: the scene node sits at the origin here, so a collider's node x/y
  # is also its world x/y. cell_size is 64.
  describe '#cell_empty?' do
    it 'is true for a cell holding no collider' do
      place_box(0, 0, :snake, width: 10, height: 10)
      tick
      expect(world.cell_empty?(300, 300)).to be(true)
    end

    it 'is false for a cell a collider sits in' do
      place_box(70, 70, :snake, width: 10, height: 10)
      tick
      expect(world.cell_empty?(100, 100)).to be(false) # same 64px cell as (70, 70)
    end

    it 'sees a circle collider too' do
      place(100, 100, :rock)
      tick
      expect(world.cell_empty?(100, 100)).to be(false)
    end

    # The broadphase buckets a box into every cell its edges touch, because a touching
    # edge *is* a contact. Occupancy is about area, so a piece filling one square must
    # leave the squares it borders free — otherwise a board of cell-sized pieces reads
    # as fully occupied.
    it 'leaves the neighbouring cells of a cell-sized collider free' do
      place_box(64, 64, :snake, width: 64, height: 64) # exactly cell (1, 1)
      tick
      expect([world.cell_empty?(64, 64), world.cell_empty?(128, 64),
              world.cell_empty?(64, 128), world.cell_empty?(0, 64)]).to eq([false, true, true, true])
    end

    # The cells are the hash's own, anchored at the world origin. A piece that does not
    # sit on that lattice straddles two cells and occupies both — which is why a board
    # wanting square-per-cell puts its own origin on a multiple of cell_size.
    it 'is false for both cells a collider straddles' do
      place_box(96, 64, :snake, width: 64, height: 64) # half in cell (1, 1), half in (2, 1)
      tick
      expect([world.cell_empty?(64, 64), world.cell_empty?(128, 64)]).to eq([false, false])
    end

    it 'is false for every cell a collider larger than one cell really covers' do
      place_box(64, 64, :snake, width: 128, height: 64) # cells (1, 1) and (2, 1)
      tick
      expect([world.cell_empty?(64, 64), world.cell_empty?(128, 64),
              world.cell_empty?(192, 64)]).to eq([false, false, true])
    end

    it 'is true before the first update has built the index' do
      place_box(70, 70, :snake, width: 10, height: 10)
      resolve_positions # the world itself is deliberately not driven
      expect(world.cell_empty?(70, 70)).to be(true)
    end

    # The same rule query_circle and nearest follow: a collider on its way out of the
    # tree no longer counts, so a corpse cannot reserve a square.
    it 'ignores a collider whose node is queued for removal' do
      place_box(70, 70, :snake, width: 10, height: 10).node.queue_free
      tick
      expect(world.cell_empty?(70, 70)).to be(true)
    end

    it 'still reports a cell occupied when only some of its colliders are freed' do
      place_box(70, 70, :snake, width: 10, height: 10).node.queue_free
      place_box(90, 90, :fruit, width: 10, height: 10)
      tick
      expect(world.cell_empty?(70, 70)).to be(false)
    end

    # A game scanning the board for a free square asks about empty cells over and over,
    # and a read must neither allocate nor grow the index (SpatialHash's bucket Hash
    # creates a bucket on a plain [] miss, which is why the hash is asked first).
    it 'allocates nothing when the cell is empty' do
      place_box(0, 0, :snake, width: 10, height: 10)
      tick
      expect { world.cell_empty?(300, 300) }.to allocate_nothing
    end

    it 'allocates nothing when the cell is occupied' do
      place_box(70, 70, :snake, width: 10, height: 10)
      tick
      expect { world.cell_empty?(70, 70) }.to allocate_nothing
    end
  end

  describe '#nearest' do
    it 'returns the closest collider within range' do
      place(100, 100, :enemy)
      closer = place(120, 100, :enemy)
      tick
      expect(world.nearest(130, 100, 100)).to be(closer)
    end

    it 'returns nil when nothing is in range' do
      place(100, 100, :enemy)
      tick
      expect(world.nearest(400, 400, 50)).to be_nil
    end

    it 'restricts to a layer when one is given' do
      place(100, 100, :tower) # nearer, wrong layer
      enemy = place(140, 100, :enemy)
      tick
      expect(world.nearest(100, 100, 100, layer: :enemy)).to be(enemy)
    end

    it 'ignores a collider queued for removal' do
      place(100, 100, :enemy).node.queue_free
      tick
      expect(world.nearest(100, 100, 50)).to be_nil
    end

    # Targeting calls this every update, so the lookup itself must not allocate.
    it 'allocates nothing per lookup' do
      place(100, 100, :enemy)
      place(140, 100, :enemy)
      tick
      expect { world.nearest(120, 100, 100, layer: :enemy) }.to allocate_nothing
    end
  end
end
