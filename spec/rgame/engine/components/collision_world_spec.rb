# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::CollisionWorld do
  # The world is a system on the scene node; colliders on child nodes register with
  # it through their tree lifecycle. Place colliders, resolve positions with a
  # phase, then tick the world and inspect the hits each collider was told about.
  let(:scene) { RGame::Engine::Node2D.new.tap { it.scene = it } }
  let(:hits)  { [] }
  let(:separations) { [] }

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
    collider.on_separated { |other| separations << [layer, other.layer] }
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
      place_box(100, 100, :player)
      place_box(110, 110, :pickup)
      tick
      expect(hits).to contain_exactly(%i[player pickup], %i[pickup player])
    end

    # The bug this convention exists for: pieces on neighbouring squares border each
    # other constantly, and an inclusive edge test reported every one of those as a
    # contact — a pickup collected by passing the square next to it.
    it 'does not report cell-sized boxes on neighbouring squares' do
      place_box(64, 64, :player, width: 64, height: 64)
      place_box(128, 64, :pickup, width: 64, height: 64) # shares an edge
      tick
      expect(hits).to be_empty
    end

    it 'reports cell-sized boxes on the same square exactly once each' do
      place_box(64, 64, :player, width: 64, height: 64)
      place_box(64, 64, :pickup, width: 64, height: 64)
      tick
      expect(hits).to contain_exactly(%i[player pickup], %i[pickup player])
    end

    it 'does not report boxes that only overlap on one axis' do
      place_box(100, 100, :player)
      place_box(110, 200, :pickup)
      tick
      expect(hits).to be_empty
    end

    # Shapes mix: the pair's narrowphase is settled by the two colliders between
    # themselves, so a circle and a box in the same world collide with each other.
    it 'reports a box overlapping a circle' do
      place_box(100, 100, :pickup) # 24x24 from (100, 100)
      place(130, 112, :bullet) # radius 12, centre 6px right of the box edge
      tick
      expect(hits).to contain_exactly(%i[pickup bullet], %i[bullet pickup])
    end

    it 'does not report a circle that clears the box' do
      place_box(100, 100, :pickup)
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
      place_box(70, 70, :player, width: 10, height: 10)
      place_box(100, 100, :pickup, width: 10, height: 10)
      place(110, 70, :rock)
      tick
      expect { world.update(0.0) }.to allocate_nothing
    end

    # The interesting half of the rule now that contacts are remembered between steps:
    # a pair that *is* touching is recorded every step for as long as it lasts, and
    # that record must cost nothing after the arrays have grown once. The listeners
    # are silent here — the pair started overlapping on the first tick, and an edge
    # fires once — so what is measured is the bookkeeping alone.
    it 'allocates nothing per step while a pair stays in contact' do
      place_box(100, 100, :player, width: 24, height: 24)
      place_box(110, 110, :pickup, width: 24, height: 24)
      tick
      expect { world.update(0.0) }.to allocate_nothing
    end
  end

  # The contract, and the reason the world remembers anything at all: a contact is two
  # edges, not a state. on_hit fires on the step a pair starts overlapping,
  # on_separated on the step it stops, and nothing fires in between — so a handler may
  # count, play a sound or spend a life, none of which survives being run again.
  describe 'contact edges' do
    it 'reports a lasting contact once, not once per step' do
      place(100, 100, :bullet)
      place(108, 100, :rock)
      3.times { tick }
      expect(hits).to contain_exactly(%i[bullet rock], %i[rock bullet])
    end

    # The duplicate this replaces: the broadphase offers a pair once per cell the two
    # share, and a pair wide enough to span three cells was reported three times in a
    # single step. These two boxes cover cells (0, 1), (1, 1) and (2, 1) at cell_size 64.
    it 'reports a pair spanning several cells once' do
      place_box(50, 100, :player, width: 100, height: 24)
      place_box(60, 100, :pickup, width: 80, height: 24)
      tick
      expect(hits).to contain_exactly(%i[player pickup], %i[pickup player])
    end

    it 'reports nothing while the pair stays apart' do
      place(100, 100, :bullet)
      place(400, 400, :rock)
      3.times { tick }
      expect([hits, separations]).to eq([[], []])
    end

    it 'reports a separation on the step the pair stops overlapping' do
      bullet = place(100, 100, :bullet)
      place(108, 100, :rock)
      tick
      bullet.node.x = 400
      tick
      expect(separations).to contain_exactly(%i[bullet rock], %i[rock bullet])
    end

    it 'reports no separation while the pair is still overlapping' do
      place(100, 100, :bullet)
      place(108, 100, :rock)
      3.times { tick }
      expect(separations).to be_empty
    end

    it 'reports a fresh contact when the pair meets again' do
      bullet = place(100, 100, :bullet)
      place(108, 100, :rock)
      tick
      bullet.node.x = 400
      tick
      bullet.node.x = 100
      tick
      expect(hits).to eq([%i[bullet rock], %i[rock bullet], %i[bullet rock], %i[rock bullet]])
    end

    # A contact also ends when the other side is destroyed, which is the case a game
    # would otherwise have to notice for itself. The freed collider is told nothing —
    # it is on its way out of the tree — so only the survivor reports.
    it 'tells the survivor when its partner is freed' do
      place(100, 100, :bullet)
      rock = place(108, 100, :rock)
      tick
      rock.node.queue_free
      tick
      expect(separations).to eq([%i[bullet rock]])
    end

    it 'tells the survivor when its partner unregisters' do
      place(100, 100, :bullet)
      rock = place(108, 100, :rock)
      tick
      world.unregister(rock)
      tick
      expect(separations).to eq([%i[bullet rock]])
    end

    # A pooled entity keeps its component objects, so a collider coming back from the
    # dead is the same one that died mid-contact. Registering clears what it was
    # holding; without that its first step would report a separation from whatever it
    # was touching in its previous life.
    it 'gives a re-registered collider a clean slate' do
      place(100, 100, :bullet)
      rock = place(108, 100, :rock)
      tick
      world.unregister(rock)
      rock.node.x = 400
      world.register(rock)
      tick
      expect(separations).to eq([%i[bullet rock]])
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
      place_box(0, 0, :player, width: 10, height: 10)
      tick
      expect(world.cell_empty?(300, 300)).to be(true)
    end

    it 'is false for a cell a collider sits in' do
      place_box(70, 70, :player, width: 10, height: 10)
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
      place_box(64, 64, :player, width: 64, height: 64) # exactly cell (1, 1)
      tick
      expect([world.cell_empty?(64, 64), world.cell_empty?(128, 64),
              world.cell_empty?(64, 128), world.cell_empty?(0, 64)]).to eq([false, true, true, true])
    end

    # The cells are the hash's own, anchored at the world origin. A piece that does not
    # sit on that lattice straddles two cells and occupies both — which is why a board
    # wanting square-per-cell puts its own origin on a multiple of cell_size.
    it 'is false for both cells a collider straddles' do
      place_box(96, 64, :player, width: 64, height: 64) # half in cell (1, 1), half in (2, 1)
      tick
      expect([world.cell_empty?(64, 64), world.cell_empty?(128, 64)]).to eq([false, false])
    end

    it 'is false for every cell a collider larger than one cell really covers' do
      place_box(64, 64, :player, width: 128, height: 64) # cells (1, 1) and (2, 1)
      tick
      expect([world.cell_empty?(64, 64), world.cell_empty?(128, 64),
              world.cell_empty?(192, 64)]).to eq([false, false, true])
    end

    it 'is true before the first update has built the index' do
      place_box(70, 70, :player, width: 10, height: 10)
      resolve_positions # the world itself is deliberately not driven
      expect(world.cell_empty?(70, 70)).to be(true)
    end

    # The same rule query_circle and nearest follow: a collider on its way out of the
    # tree no longer counts, so a corpse cannot reserve a square.
    it 'ignores a collider whose node is queued for removal' do
      place_box(70, 70, :player, width: 10, height: 10).node.queue_free
      tick
      expect(world.cell_empty?(70, 70)).to be(true)
    end

    it 'still reports a cell occupied when only some of its colliders are freed' do
      place_box(70, 70, :player, width: 10, height: 10).node.queue_free
      place_box(90, 90, :pickup, width: 10, height: 10)
      tick
      expect(world.cell_empty?(70, 70)).to be(false)
    end

    # A game scanning the board for a free square asks about empty cells over and over,
    # and a read must neither allocate nor grow the index (SpatialHash's bucket Hash
    # creates a bucket on a plain [] miss, which is why the hash is asked first).
    it 'allocates nothing when the cell is empty' do
      place_box(0, 0, :player, width: 10, height: 10)
      tick
      expect { world.cell_empty?(300, 300) }.to allocate_nothing
    end

    it 'allocates nothing when the cell is occupied' do
      place_box(70, 70, :player, width: 10, height: 10)
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
      place(100, 100, :ally) # nearer, wrong layer
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

  # The rectangular query a blocker source asks: "what is bucketed near this box". No
  # narrowphase at all — the bucket walk is the answer, and refining it is the caller's.
  describe '#query_box' do
    def in_box(x, y, w, h)
      found = []
      world.query_box(x, y, w, h) { |collider| found << collider }
      found
    end

    it 'yields a collider bucketed in a cell the region covers' do
      near = place_box(100, 100, :npc)
      place_box(400, 400, :npc) # a different cell
      tick
      expect(in_box(100, 100, 10, 10)).to eq([near])
    end

    it 'yields nothing from cells the region does not reach' do
      place_box(400, 400, :npc)
      tick
      expect(in_box(0, 0, 10, 10)).to be_empty
    end

    it 'skips a collider whose node is queued for removal' do
      place_box(100, 100, :npc).node.queue_free
      tick
      expect(in_box(100, 100, 10, 10)).to be_empty
    end

    it 'yields nothing before the first update has built the index' do
      place_box(100, 100, :npc)
      resolve_positions
      expect(in_box(100, 100, 10, 10)).to be_empty
    end

    # A resolver queries once per axis per actor per step.
    it 'allocates nothing per query' do
      place_box(100, 100, :npc)
      tick
      expect { world.query_box(100, 100, 10, 10) { |_collider| nil } }.to allocate_nothing
    end
  end

  # Buckets are filled once per step, so a collider that moves afterwards is still
  # bucketed where it was and a query over the cells it has left does not reach it.
  # Re-indexing is what makes a mid-step query exact; the mover passes the box it was
  # bucketed at, so nothing here has to have remembered one.
  describe '#reindex' do
    def in_box(x, y, w, h)
      found = []
      world.query_box(x, y, w, h) { |collider| found << collider }
      found
    end

    # The measurement the whole mechanism exists for: without the reindex line this
    # example's second expectation is [] — the mover is genuinely in the far cell and
    # the index says otherwise.
    it 'finds a collider at its new position within the same step' do
      mover = place_box(0, 0, :npc)
      tick
      mover.node.x = 400
      mover.node.y = 400
      mover.node.update(0.0) # resolve the world transform the AABB is read from
      world.reindex(mover, 0, 0, mover.aabb_w, mover.aabb_h)
      expect(in_box(400, 400, 10, 10)).to eq([mover])
    end

    it 'stops finding it at the cell it left' do
      mover = place_box(0, 0, :npc)
      tick
      mover.node.x = 400
      mover.node.y = 400
      mover.node.update(0.0)
      world.reindex(mover, 0, 0, mover.aabb_w, mover.aabb_h)
      expect(in_box(0, 0, 10, 10)).to be_empty
    end

    it 'leaves the colliders that did not move where they are' do
      mover = place_box(0, 0, :npc)
      still = place_box(10, 10, :npc)
      tick
      mover.node.x = 400
      mover.node.update(0.0)
      world.reindex(mover, 0, 0, mover.aabb_w, mover.aabb_h)
      expect(in_box(10, 10, 4, 4)).to eq([still])
    end

    # Called from CollisionSystem#move, so it is on the per-actor per-step path.
    it 'allocates nothing' do
      mover = place_box(0, 0, :npc)
      tick
      world.reindex(mover, 0, 0, mover.aabb_w, mover.aabb_h) # warm the buckets it lands in
      expect { world.reindex(mover, 0, 0, mover.aabb_w, mover.aabb_h) }.to allocate_nothing
    end
  end
end
