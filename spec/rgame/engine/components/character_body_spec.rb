# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::CharacterBody do
  # Unit scope: the body turns a movement intent into a step, and `blocked_by:` decides
  # where that step is allowed to land. Both halves are here because they are one class —
  # an unblocked body writes to the node, and a blocked one builds a resolver at attach
  # and hands itself to it. The tile-vs-box maths itself is tile_blockers_spec's and the
  # actor-vs-actor maths is actor_blockers_spec's.
  #
  # The actor hangs under a root, because the body resolves in **world** space and a
  # parentless node is pinned to the world origin whatever its own x/y say. The root is
  # also the scene, so a real system mounted on it is found the way a game's would be.
  let(:root) { RGame::Engine::Node2D.new.tap { it.scene = it } }
  let(:node) { RGame::Engine::Node2D.new(x: 100.0, y: 100.0) }

  # Systems this node should see that the tree does not really carry. Anything not named
  # falls through to the real lookup, so a spec can mount a real CollisionWorld on the
  # scene and still hand the body a doubled TileWorld.
  def mount(systems, on: node)
    allow(on).to receive(:system).and_wrap_original do |original, klass|
      systems[klass] || original.call(klass)
    end
  end

  # TileWorld *is* a WorldBounds, and Node2D#system finds it by is_a? — which a verifying
  # double is not — so the two names are answered with the same object.
  def mount_tiles(world, on: node)
    mount({ RGame::Engine::Components::TileWorld => world,
            RGame::Engine::Components::WorldBounds => world }, on: on)
  end

  # A doubled TileWorld whose blocker source is real: what a body borrows from a tile
  # world is its Engine::TileBlockers, and the arithmetic that runs is that class's.
  def tile_world(solid: ->(_col, _row) { false }, width: 1000, height: 1000)
    instance_double(
      RGame::Engine::Components::TileWorld,
      blockers: RGame::Engine::TileBlockers.new(tile_width: 16, tile_height: 16, solid: solid),
      world_width: width, world_height: height
    )
  end

  # Put the actor in the tree and bring the whole thing live, so world positions resolve
  # from real parents rather than from a node standing on its own.
  def enter(child = node, parent: root)
    parent.add_node(child)
    parent.enter_tree
  end

  describe 'an unblocked body — the default' do
    let(:body) { described_class.new(speed: 50.0) }

    before do
      node.add_component(body)
      enter
    end

    it 'moves the node by the intent scaled by speed and dt' do
      body.set_intent(1.0, -0.5)
      body.update(0.5)
      expect([node.x, node.y]).to eq([125.0, 87.5]) # 1.0 * 50 * 0.5, -0.5 * 50 * 0.5
    end

    it 'does nothing when the intent is zero' do
      body.set_intent(0.0, 0.0)
      body.update(0.5)
      expect([node.x, node.y]).to eq([100.0, 100.0])
    end

    it 'exposes the intent as the facing for the animator' do
      body.set_intent(-1.0, 1.0)
      expect([body.move_x, body.move_y]).to eq([-1.0, 1.0])
    end

    # The three things an actor with nothing to bump into must not need: a sprite to be
    # sized by, a collider to carry a shape, and a system on the scene to resolve
    # against. This node has none of them — a bare Node2D with one component — and that
    # is what `blocked_by: []` buys.
    describe 'what it does not need' do
      it 'moves with no sprite size on the node' do
        expect(node.width).to be_zero
        body.set_intent(1.0, 0.0)
        expect { body.update(0.1) }.to change(node, :x).by(5.0)
      end

      it 'moves with no world system on the scene' do
        expect(node.system(RGame::Engine::Components::TileWorld)).to be_nil
        body.set_intent(0.0, 1.0)
        expect { body.update(0.1) }.to change(node, :y).by(5.0)
      end

      it 'moves with no collider on the node' do
        expect(node.get_component(RGame::Engine::Components::BoxCollider)).to be_nil
        body.set_intent(1.0, 0.0)
        expect { body.update(0.1) }.to change(node, :x).by(5.0)
      end
    end
  end

  describe 'blocked_by: [:tiles]' do
    # A wall in column 8, x 128..144. The node's box is offset (8, 16) from its origin,
    # so the origin at (100, 100) puts the box at (108, 116) with its right edge at 124.
    let(:world)    { tile_world(solid: ->(col, _row) { col == 8 }) }
    let(:collider) { RGame::Engine::Components::BoxCollider.new(width: 16, height: 16, offset_x: 8, offset_y: 16) }
    let(:body)     { described_class.new(speed: 50.0, blocked_by: [:tiles]) }

    before do
      mount_tiles(world)
      node.add_component(collider)
      node.add_component(body)
      enter
    end

    # A 10px step, which would put the box's right edge at 134 — past the wall's near
    # edge, and inside its column. TileBlockers assumes a step smaller than a tile.
    it 'stops the step flush against a solid tile' do
      body.set_intent(1.0, 0.0)
      body.update(0.2)
      expect(node.x).to eq(104.0) # the box right edge rests on the wall at 128
    end

    it 'moves freely where nothing is solid' do
      body.set_intent(0.0, 1.0)
      body.update(0.5)
      expect(node.y).to eq(125.0)
    end

    it 'does nothing when the intent is zero' do
      body.set_intent(0.0, 0.0)
      body.update(0.5)
      expect([node.x, node.y]).to eq([100.0, 100.0])
    end

    it 'takes a bare symbol as readily as a list' do
      bare = RGame::Engine::Node2D.new
      allow(bare).to receive(:system) { |klass| klass == RGame::Engine::Components::TileWorld ? world : nil }
      bare.add_component(RGame::Engine::Components::BoxCollider.new(width: 4, height: 4))
      bare.add_component(described_class.new(speed: 50.0, blocked_by: :tiles))
      expect { enter(bare) }.not_to raise_error
    end

    describe 'the actor adapter CollisionSystem#move drives' do
      it 'reads x/y from the node' do
        expect([body.x, body.y]).to eq([100.0, 100.0])
      end

      it 'writes a resolved position back to the node' do
        body.x = 140.0
        body.y = 160.0
        expect([node.x, node.y]).to eq([140.0, 160.0])
      end

      it 'resolves with the sibling collider’s box, not one of its own' do
        expect(body.collision_box).to be(collider.box)
      end

      # The shape has one owner, so retuning it retunes both what stops a step and what
      # reports a contact. Under the old two-component arrangement these were two boxes
      # and this assignment moved only one of them.
      it 'follows a box reassigned on the collider' do
        retuned = RGame::Engine::CollisionBox.new(width: 4, height: 4, offset_x: 1, offset_y: 2)
        collider.box = retuned
        expect(body.collision_box).to be(retuned)
      end
    end
  end

  # Everything else about collision is in world space: the tile grid is a world-coordinate
  # grid and BoxCollider#aabb_x reports node.world_x + the box offset. So the adapter is
  # too, and these pin what that means from underneath an ancestor that is not at the
  # origin — the case nothing in the repository builds today, and the one that would
  # otherwise resolve a step against a map shifted by however far the ancestor sits.
  describe 'the adapter is in world space' do
    let(:container) { RGame::Engine::Node2D.new(x: 100.0, y: 50.0) }
    let(:collider)  { RGame::Engine::Components::BoxCollider.new(width: 16, height: 16) }
    let(:body)      { described_class.new(speed: 50.0, blocked_by: [:tiles]) }

    # A resolver of this spec's own rather than the body's: what these are about is which
    # numbers reach the tile arithmetic, so the tiles have to be real too. One solid
    # column at x 128..144.
    def resolver
      @resolver ||= RGame::Engine::CollisionSystem.new(
        blockers: RGame::Engine::TileBlockers.new(
          tile_width: 16, tile_height: 16, solid: ->(col, _row) { col == 8 }
        )
      )
    end

    before do
      mount_tiles(tile_world)
      node.add_component(collider)
      node.add_component(body)
      root.add_node(container)
      container.add_node(node)
      root.enter_tree
    end

    it 'reports the node’s world position, not its local one' do
      expect([body.x, body.y]).to eq([200.0, 150.0]) # local (100, 100) under (100, 50)
    end

    # Local x 10 under a container at x 100 is world 110, whose box right edge is at 126.
    # A +10 step would cross the wall at 128, so it lands with the right edge on it: world
    # 112, which is local 12. A body reading its local x would have thought itself at 10,
    # a whole hundred pixels short of the wall, and walked straight through it.
    it 'resolves against tiles at its world position' do
      node.x = 10.0
      resolver.move(body, 10.0, 0.0)
      expect(node.x).to eq(12.0)
      expect(body.x).to eq(112.0)
    end

    # Writing back is a translation of the local position, so the node stays in the frame
    # its parent put it in and moves by exactly the resolved delta.
    it 'writes a resolved position back as a local translation' do
      body.x = 260.0
      body.y = 170.0
      expect([node.x, node.y]).to eq([160.0, 120.0])
      expect([body.x, body.y]).to eq([260.0, 170.0])
    end

    # The documented limit, pinned so it is a decision rather than a surprise. Under a
    # rotated ancestor the world-space delta is applied to local axes the rotation has
    # turned, so a +10 world step moves the node ten *local* units — which the rotation
    # then points somewhere else. An actor under a rotated ancestor is already outside
    # what an axis-aligned box supports; a circle is what a spinning thing wants.
    it 'applies a resolved delta on the ancestor’s own axes when it is rotated' do
      container.angle = Math::PI / 2
      node.x = 0.0
      node.y = 0.0
      body.x = body.x + 10.0 # reads the world position, writes a local translation
      expect(node.x).to eq(10.0)             # ten local units...
      expect(body.y.round(6)).to eq(60.0)    # ...which the quarter turn has pointed at +y
    end

    # world_x is cached and self-invalidating, so reading it per step must not have
    # introduced a recompute that allocates.
    it 'allocates nothing per move' do
      resolver.move(body, 1.0, 1.0) # warm the transform cache and the resolver
      expect { resolver.move(body, 1.0, 1.0) }.to allocate_nothing
    end
  end

  # A layer name means the scene's CollisionWorld: the body is stopped flush by any box
  # collider wearing that layer, the way a solid tile stops it. These mount a real
  # CollisionWorld, because what is being pinned is the wiring — the body finding the
  # world, excluding its own collider, and re-indexing itself afterwards.
  describe 'blocked_by: a collider layer' do
    let(:collision_world) { root.add_component(RGame::Engine::Components::CollisionWorld.new(cell_size: 64)) }
    let(:body) { described_class.new(speed: 15.0, blocked_by: [:npc]) }

    # An actor: a 10x10 box at the node's origin, plus whatever body is given.
    def actor(x, y, layer:, body: nil)
      actor_node = RGame::Engine::Node2D.new(x: x, y: y)
      actor_node.add_component(RGame::Engine::Components::BoxCollider.new(width: 10, height: 10, layer: layer))
      actor_node.add_component(body) if body
      root.add_node(actor_node)
      actor_node
    end

    # The scene's own order: the world rebuilds its index, then the children take steps.
    def tick(dt = 1.0)
      root.children.each { it.update(0.0) } # resolve world transforms, as a scene's pass does
      collision_world.update(dt)
      root.children.each { it.update(dt) }
    end

    before do
      collision_world
      root.enter_tree
    end

    it 'stops the step flush against a collider on that layer' do
      hero = actor(100.0, 100.0, layer: :hero, body: body)
      actor(120.0, 100.0, layer: :npc)
      body.set_intent(1.0, 0.0)
      tick
      expect(hero.x).to eq(110.0) # a 15px step, stopped with its right edge on the NPC
    end

    it 'is not stopped by a collider on a layer it did not declare' do
      hero = actor(100.0, 100.0, layer: :hero, body: body)
      actor(120.0, 100.0, layer: :pickup)
      body.set_intent(1.0, 0.0)
      tick
      expect(hero.x).to eq(115.0)
    end

    # A layer is a declaration about what *may* stop this body. One that happens to hold
    # nothing is ordinary, not a misconfiguration.
    it 'moves freely when the declared layer is empty' do
      hero = actor(100.0, 100.0, layer: :hero, body: body)
      body.set_intent(1.0, 0.0)
      tick
      expect(hero.x).to eq(115.0)
    end

    # What lets a crowd of NPCs all declare blocked_by: [:npc].
    it 'is not stopped by its own collider on a declared layer' do
      hero = actor(100.0, 100.0, layer: :npc, body: body)
      body.set_intent(1.0, 0.0)
      tick
      expect(hero.x).to eq(115.0)
    end

    # A scene with a broadphase and no bounds at all is ordinary — test_projects/snake is
    # one — so an actor-blocked body must not need them.
    it 'is not clamped, and does not raise, in a scene with no WorldBounds' do
      expect(root.get_component(RGame::Engine::Components::WorldBounds)).to be_nil
      fast = described_class.new(speed: 1000.0, blocked_by: [:npc])
      hero = actor(100.0, 100.0, layer: :hero, body: fast)
      fast.set_intent(-1.0, 0.0)
      tick
      expect(hero.x).to eq(-900.0)
    end

    # Blocking stops the mover and never moves what it hit, so a pair walking into each
    # other ends up touching with neither displaced.
    it 'stops both of two bodies walking into each other' do
      left_body  = described_class.new(speed: 15.0, blocked_by: [:npc])
      right_body = described_class.new(speed: 15.0, blocked_by: [:npc])
      left  = actor(100.0, 100.0, layer: :npc, body: left_body)
      right = actor(120.0, 100.0, layer: :npc, body: right_body)
      left_body.set_intent(1.0, 0.0)
      right_body.set_intent(-1.0, 0.0)
      tick
      expect([left.x, right.x]).to eq([110.0, 120.0])
    end

    # The other half of that: whoever moves first re-indexes itself, so the second finds
    # it where it now is rather than where the index was built. Without the re-index the
    # follower walks into the space the leader has taken and the two overlap.
    it 'sees a blocker that already moved this step' do
      leader_body   = described_class.new(speed: 15.0, blocked_by: [:npc])
      follower_body = described_class.new(speed: 15.0, blocked_by: [:npc])
      actor(100.0, 100.0, layer: :npc, body: leader_body)
      follower = actor(75.0, 100.0, layer: :npc, body: follower_body)
      leader_body.set_intent(-1.0, 0.0)  # steps back to 85
      follower_body.set_intent(1.0, 0.0) # would reach 90, where the leader now is
      tick
      expect(follower.x).to eq(75.0)
    end
  end

  describe 'blocked_by: %i[tiles npc]' do
    # Walls at columns and rows 5 and 8 — so x 80..96 and 128..144, and the same in y —
    # with the hero in the free square between them.
    let(:world) { tile_world(solid: ->(col, row) { [5, 8].include?(col) || [5, 8].include?(row) }) }
    let(:body) { described_class.new(speed: 20.0, blocked_by: %i[tiles npc]) }
    let(:hero) { RGame::Engine::Node2D.new(x: 100.0, y: 100.0) }

    def collision_world
      @collision_world ||= root.add_component(RGame::Engine::Components::CollisionWorld.new(cell_size: 64))
    end

    def npc_at(x, y, width: 10, height: 10)
      npc = RGame::Engine::Node2D.new(x: x, y: y)
      npc.add_component(RGame::Engine::Components::BoxCollider.new(width: width, height: height, layer: :npc))
      root.add_node(npc)
    end

    def tick(dt = 1.0)
      root.children.each { it.update(0.0) }
      collision_world.update(dt)
      root.children.each { it.update(dt) }
    end

    before do
      collision_world
      mount_tiles(world, on: hero)
      hero.add_component(RGame::Engine::Components::BoxCollider.new(width: 10, height: 10, layer: :hero))
      hero.add_component(body)
      root.add_node(hero)
      root.enter_tree
    end

    # A 20px step, so both blockers are genuinely in reach in each of these and the
    # answer is a comparison rather than the only candidate there was. Where the *wall*
    # wins, the NPC has to be a wide one: anything narrow whose edge is beyond a solid
    # column can only be reached by a step that tunnels the column, which TileBlockers
    # does not resolve.
    it 'stops at the NPC when it is the nearer of the two, moving right' do
      npc_at(120.0, 100.0) # its left edge at 120, against the wall's at 128
      body.set_intent(1.0, 0.0)
      tick
      expect(hero.x).to eq(110.0)
    end

    it 'stops at the wall when it is the nearer of the two, moving left' do
      npc_at(59.0, 100.0, width: 36) # its right edge at 95, against the wall's at 96
      body.set_intent(-1.0, 0.0)
      tick
      expect(hero.x).to eq(96.0)
    end

    it 'stops at the NPC when it is the nearer of the two, moving down' do
      npc_at(100.0, 120.0) # its top edge at 120, against the wall's at 128
      body.set_intent(0.0, 1.0)
      tick
      expect(hero.y).to eq(110.0)
    end

    it 'stops at the wall when it is the nearer of the two, moving up' do
      npc_at(100.0, 59.0, height: 36) # its bottom edge at 95, against the wall's at 96
      body.set_intent(0.0, -1.0)
      tick
      expect(hero.y).to eq(96.0)
    end

    # Per actor per frame, with a broadphase query on each axis inside it. The body is
    # driven into the NPC and left pressing against it, which is the steady state the
    # matcher wants: a body still travelling would enter fresh broadphase cells and the
    # buckets built for those would be counted as the leak.
    it 'allocates nothing per update with both kinds of blocker declared' do
      npc_at(120.0, 100.0)
      body.set_intent(1.0, 0.0)
      tick
      expect { body.update(1.0) }.to allocate_nothing
    end
  end

  # The edge of the world, declared like anything else. A body that does not name it walks
  # out of the world, which is the point: nothing holds an actor anywhere it did not ask
  # to be held, so the components that read the same bounds and act on the node instead —
  # ScreenWrap, DespawnOffscreen — are no longer contradicted by a clamp nobody asked for.
  describe 'blocked_by: [:bounds]' do
    let(:body) { described_class.new(speed: 1000.0, blocked_by: [:bounds]) }
    let(:collider) { RGame::Engine::Components::BoxCollider.new(width: 10, height: 10) }

    def mount_bounds(width: 200, height: 100, on: node)
      world = RGame::Engine::Components::World.new(width: width, height: height)
      mount({ RGame::Engine::Components::WorldBounds => world }, on: on)
      world
    end

    def step(intent_x, intent_y)
      body.set_intent(intent_x, intent_y)
      body.update(1.0)
      [node.x, node.y]
    end

    before do
      mount_bounds
      node.add_component(collider)
      node.add_component(body)
      enter
    end

    it 'stops flush against the left edge' do
      expect(step(-1.0, 0.0).first).to eq(0.0)
    end

    it 'stops flush against the right edge' do
      expect(step(1.0, 0.0).first).to eq(190.0) # 200 - the box's 10
    end

    it 'stops flush against the top edge' do
      expect(step(0.0, -1.0).last).to eq(0.0)
    end

    it 'stops flush against the bottom edge' do
      expect(step(0.0, 1.0).last).to eq(90.0)
    end

    # It bounds the *world*, not a region shifted by wherever the actor's container
    # happens to sit — which is true because the body resolves in world space.
    it 'bounds the world region for a body under an offset ancestor' do
      container = RGame::Engine::Node2D.new(x: 60.0, y: 20.0)
      inner = RGame::Engine::Node2D.new(x: 40.0, y: 30.0) # world (100, 50)
      mount_bounds(on: inner)
      inner.add_component(RGame::Engine::Components::BoxCollider.new(width: 10, height: 10))
      moving = inner.add_component(described_class.new(speed: 1000.0, blocked_by: [:bounds]))
      root.add_node(container)
      container.add_node(inner)
      root.enter_tree
      moving.set_intent(1.0, 0.0)
      moving.update(1.0)
      expect([inner.x, inner.world_x]).to eq([130.0, 190.0]) # world 190, local 190 - 60
    end
  end

  describe 'blocked_by: %i[tiles bounds]' do
    # A 200x100 map with a wall in column 5, x 80..96.
    let(:world) { tile_world(solid: ->(col, _row) { col == 5 }, width: 200, height: 100) }
    let(:body)  { described_class.new(speed: 1000.0, blocked_by: %i[tiles bounds]) }

    before do
      mount_tiles(world)
      node.add_component(RGame::Engine::Components::BoxCollider.new(width: 10, height: 10))
      node.add_component(body)
      enter
    end

    it 'stops at the wall when it is nearer than the world edge' do
      body.set_intent(-1.0, 0.0)
      body.update(0.01) # a 10px step, smaller than a tile
      expect(node.x).to eq(96.0)
    end

    it 'stops at the world edge when nothing else is in the way' do
      body.set_intent(1.0, 0.0)
      body.update(1.0)
      expect(node.x).to eq(190.0)
    end
  end

  # The other half of the same decision: a body that did not name the edge is not held by
  # it. Nothing in the repository relied on the clamp — every map here has a solid border,
  # so it had never once fired in a game that could reach it.
  describe 'a body that does not declare :bounds' do
    it 'walks past the edge of the world it is in' do
      mount_tiles(tile_world(width: 200, height: 100))
      node.add_component(RGame::Engine::Components::BoxCollider.new(width: 10, height: 10))
      body = node.add_component(described_class.new(speed: 1000.0, blocked_by: [:tiles]))
      enter
      body.set_intent(1.0, 0.0)
      body.update(1.0)
      expect(node.x).to eq(1100.0)
    end
  end

  # Two components reading the same bounds and acting on different things. The engine
  # cannot reconcile them, so what it does instead is make the contradiction something a
  # game has to ask for twice: a wrapping game declares no `:bounds` and nothing holds it.
  describe 'a bounds-blocked body under a ScreenWrap' do
    it 'is wrapped anyway, because ScreenWrap moves the node after the step' do
      world = RGame::Engine::Components::World.new(width: 200, height: 100)
      mount({ RGame::Engine::Components::WorldBounds => world })
      # A feet-shaped box: narrower than the node, so its offset is positive and a body
      # held at the world edge leaves node.x negative — which is what ScreenWrap reads.
      node.add_component(RGame::Engine::Components::BoxCollider.new(width: 10, height: 10, offset_x: 3))
      body = node.add_component(described_class.new(speed: 1000.0, blocked_by: [:bounds]))
      node.add_component(RGame::Engine::Components::ScreenWrap.new)
      enter
      body.set_intent(-1.0, 0.0)
      node.update(1.0)
      expect(node.x).to eq(200.0) # the body stopped it at -3; the wrap sent it to the far edge
    end
  end

  # A body that cannot be blocked the way it was told to says so at attach, rather than
  # falling back to free movement: an actor walking through walls looks like a collision
  # bug, and the cause would be a scene three files away.
  describe 'what it refuses at attach' do
    it 'refuses :tiles on a scene with no TileWorld, naming both' do
      mount({})
      node.add_component(RGame::Engine::Components::BoxCollider.new(width: 4, height: 4))
      node.add_component(described_class.new(speed: 50.0, blocked_by: [:tiles]))
      expect { enter }.to raise_error(/blocked_by :tiles.*no TileWorld/m)
    end

    it 'refuses :tiles on a node with no collider to resolve' do
      mount_tiles(tile_world)
      node.add_component(described_class.new(speed: 50.0, blocked_by: [:tiles]))
      expect { enter }.to raise_error(/needs a RGame::Engine::Components::BoxCollider/)
    end

    it 'refuses :bounds on a scene with no WorldBounds, naming both' do
      mount({})
      node.add_component(RGame::Engine::Components::BoxCollider.new(width: 4, height: 4))
      node.add_component(described_class.new(speed: 50.0, blocked_by: [:bounds]))
      expect { enter }.to raise_error(/blocked_by :bounds.*no world bounds/m)
    end

    # The mirror of the :tiles raise, and the one a game is likelier to hit: a layer name
    # in a scene that never mounted a broadphase would otherwise be a body silently
    # blocked by nothing at all.
    it 'refuses a collider layer on a scene with no CollisionWorld, naming the layer' do
      mount({})
      node.add_component(RGame::Engine::Components::BoxCollider.new(width: 4, height: 4))
      node.add_component(described_class.new(speed: 50.0, blocked_by: [:npc]))
      expect { enter }.to raise_error(/blocked_by :npc.*no CollisionWorld/m)
    end
  end
end
