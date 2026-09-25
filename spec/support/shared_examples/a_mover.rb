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
# The :gaps group states that each of them stops at the edge of a map's floor, alone and
# beside the map's solid tiles.
#
# The platform group states that each of them, moving a Platform, carries a rider by exactly
# its own step, in either update order, and that the carry is none of the rider's business
# when a wall stops it.
#
# The pushes: group states that each of them can push, and that declaring it changes nothing
# about a wall that cannot be pushed.
#
# The heading group states the other half they share: whichever way the step goes, the
# mover's heading points that way.
#
# ## What the host must provide
#
#   it_behaves_like 'a mover' do
#     def build_mover(blocked_by:, pushes: [], heading: [1, 0]) = ...
#     def start_mover(mover, heading) = ...   # optional
#   end
#
# `start_mover` runs once the mover has entered the tree, with the heading it was built
# with. A mover that clears on attach what it was told, as a CharacterBody stands still,
# is told its heading there.
#
# A mover, unattached, that carries its node from wherever the node stands — (170, 100) —
# **in the direction of `heading`**, for at least four seconds: rightwards at 60 px/s for
# [1, 0], downwards for [0, 1], and down and to the right for [1, 1]. How fast the diagonal
# goes is the mover's own business. The group builds everything else: a scene with a real
# CollisionWorld, a 16x400 `:wall` collider whose left edge is at x = 200, and a node with a
# 16x16 box. At 60 ticks a second that is one pixel a step, and the box meets the wall after
# fourteen. Some examples add a 200x16 `:floor` whose top edge is at y = 130, fourteen pixels
# below the box, so the wall and the floor make a corner the diagonal walks into.
#
# The names below are prefixed so they cannot shadow, or be shadowed by, the host spec's
# own `node` and `root`.
RSpec.shared_examples 'a mover' do
  def mover_dt = 1.0 / 60

  let(:mover_scene) { RGame::Engine::Node2D.new.tap { it.scene = it } }
  let(:mover_node) { RGame::Engine::Node2D.new(x: 170.0, y: 100.0) }
  let(:wall_node) { RGame::Engine::Node2D.new(x: 200.0, y: 0.0) }
  let(:wall) { RGame::Engine::Components::BoxCollider.new(width: 16, height: 400, layer: :wall) }

  # A method rather than a let, which would put the wall-only groups one memoized helper over
  # RuboCop's limit for a collider they never read. Exempted in spec/spec_style_spec.rb.
  def floor = @floor ||= RGame::Engine::Components::BoxCollider.new(width: 200, height: 16, layer: :floor)

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
    mover_scene.add_node(RGame::Engine::Node2D.new(x: 0.0, y: 130.0).tap { it.add_component(floor) })
    mover_node.add_component(mover)
    mover_scene.add_node(mover_node)
    mover_scene.enter_tree
    mover
  end

  def enter_mover(heading: [1, 0], **)
    mover = enter(build_mover(heading:, **))
    start_mover(mover, heading)
    mover
  end

  def start_mover(_mover, _heading); end

  # A whole scene tick: the CollisionWorld rebuilds its index, then the nodes move.
  def run_ticks(count) = count.times { mover_scene.update(mover_dt) }

  describe 'declaring nothing' do
    it 'passes through the wall' do
      mount_collision_world
      add_box
      enter_mover(blocked_by: [])
      run_ticks(60)
      expect(mover_node.x).to be_within(1e-6).of(230.0)
    end

    it 'needs no collider and no collision system' do
      enter_mover(blocked_by: [])
      run_ticks(60)
      expect(mover_node.x).to be_within(1e-6).of(230.0)
    end
  end

  describe 'blocked_by: [:wall]' do
    let!(:mover) do
      mount_collision_world
      add_box
      enter_mover(blocked_by: [:wall])
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
      expect { mover._update(mover_dt) }.to allocate_nothing
    end
  end

  # A map with a gap one tile wide, whose cell starts at x = `gap` * 16, and a solid tile at
  # x = `wall` * 16, in every row the box crosses. The box's centre starts at x = 178.
  describe 'blocked_by: [:gaps]' do
    def mount_tile_world(gap:, wall: nil)
      rows = Array.new(10) { Array.new(15) { |col| { gap => '~', wall => '#' }.fetch(col, '.') }.join }
      mover_scene.add_component(
        RGame::Engine::Components::TileWorld.new(map: WalledTileMap.build(rows), tilemap_id: :map)
      )
    end

    before do
      mount_collision_world
      add_box
      mover_node.add_component(RGame::Engine::Components::Footing.new)
    end

    it 'stops the centre of the box short of the gap, and says the gaps stopped it once' do
      mount_tile_world(gap: 13)
      mover = enter_mover(blocked_by: [:gaps])
      reports = []
      mover.on_blocked { |by, axis| reports << [by.layer, by.node, axis] }
      run_ticks(60)
      expect([mover_node.x, reports]).to match([be_within(1e-6).of(200.0), [[:gaps, nil, :x]]])
    end

    it 'stops at a solid tile nearer than the gap, beside :tiles' do
      mount_tile_world(gap: 13, wall: 12)
      enter_mover(blocked_by: %i[tiles gaps])
      run_ticks(60)
      expect(mover_node.x).to eq(176.0)
    end

    it 'stops at a gap nearer than a solid tile, beside :tiles' do
      mount_tile_world(gap: 12, wall: 13)
      enter_mover(blocked_by: %i[tiles gaps])
      run_ticks(60)
      expect(mover_node.x).to be_within(1e-6).of(184.0)
    end

    it 'allocates nothing on a step pressed against the gap' do
      mount_tile_world(gap: 13)
      mover = enter_mover(blocked_by: [:gaps])
      run_ticks(60)
      expect { mover._update(mover_dt) }.to allocate_nothing
    end
  end

  # The whole map is a chasm, so the mover's own 16x16 box is the only floor. The rider's
  # 8x8 box starts 4 px inside it, and a :wall rider meets the wall's left edge at x = 200
  # once the platform has gone 18 px.
  describe 'moving a Platform' do
    def mount_chasm
      rows = Array.new(10) { '~' * 20 }
      mover_scene.add_component(
        RGame::Engine::Components::TileWorld.new(map: WalledTileMap.build(rows), tilemap_id: :map)
      )
    end

    def rider(blocked_by: [])
      RGame::Engine::Node2D.new(x: 174.0, y: 104.0).tap do |node|
        node.add_component(RGame::Engine::Components::BoxCollider.new(width: 8, height: 8, layer: :rider))
        node.add_component(RGame::Engine::Components::Footing.new)
        node.add_component(RGame::Engine::Components::CharacterBody.new(speed: 60, blocked_by:))
      end
    end

    before do
      mount_chasm
      mount_collision_world
      add_box
      mover_node.add_component(RGame::Engine::Components::Platform.new)
    end

    %i[before after].each do |order|
      it "carries a rider by exactly its own step, with the rider updating #{order} it" do
        passenger = rider
        mover_scene.add_node(passenger) if order == :before
        enter_mover(blocked_by: [])
        mover_scene.add_node(passenger) if order == :after
        run_ticks(1) # the tick the rider boards
        gap_x = passenger.x - mover_node.x
        gap_y = passenger.y - mover_node.y
        run_ticks(30)
        expect([passenger.x - mover_node.x, passenger.y - mover_node.y])
          .to match([be_within(1e-9).of(gap_x), be_within(1e-9).of(gap_y)])
      end
    end

    it 'fires no on_blocked and changes no stopped? on a rider a wall stops' do
      passenger = rider(blocked_by: [:wall])
      mover_scene.add_node(passenger)
      enter_mover(blocked_by: [])
      body = passenger.get_component(RGame::Engine::Components::CharacterBody)
      blocked = 0
      body.on_blocked { blocked += 1 }
      run_ticks(24)
      expect([passenger.x, blocked, body.stopped?]).to eq([192.0, 0, false])
    end

    # Two hundred steps, which a PathFollow walks well short of its road's end.
    it 'allocates nothing carrying a rider' do
      mover_scene.add_node(rider)
      mover = enter_mover(blocked_by: [])
      run_ticks(2)
      expect { mover._update(mover_dt) }.to allocate_nothing.over(200)
    end
  end

  # on_blocked's second argument. A single collider stops one axis a step — CollisionSystem
  # snaps x flush before it resolves y, so the box no longer overlaps on the far axis — and
  # :both is the map's, pinned in character_body_spec where a scene has tiles.
  describe 'which axis stopped the step' do
    def blocked_on(heading, blocked_by)
      mount_collision_world
      add_box
      mover = enter_mover(blocked_by: blocked_by, heading: heading)
      reports = []
      mover.on_blocked { |by, axis| reports << [by, axis] }
      run_ticks(60)
      reports
    end

    it 'is :x for a push into the wall' do
      expect(blocked_on([1, 0], [:wall])).to eq([[wall, :x]])
    end

    it 'is :y for a push into the floor' do
      expect(blocked_on([0, 1], [:floor])).to eq([[floor, :y]])
    end

    # The wall and the floor are both fourteen pixels off, so the diagonal meets them on the
    # same step. That is what lets a PathFollow in: a blocked step rewinds its walk, so a
    # follower the wall stops first aims at the same point again and never reaches a floor
    # further down.
    it 'reports each collider of a corner with the axis it stopped' do
      expect(blocked_on([1, 1], %i[wall floor])).to eq([[wall, :x], [floor, :y]])
    end

    # The steady press above never emits, so the step that does gets its own measurement.
    # Fourteen steps leave the box flush and not yet blocked; the fifteenth pushes into the
    # wall, and the count says it was that step which started the block.
    it 'allocates nothing on the step that starts a block' do
      mount_collision_world
      add_box
      mover = enter_mover(blocked_by: [:wall])
      started = 0
      mover.on_blocked { started += 1 }
      run_ticks(14)
      expect { mover._update(mover_dt) }.to allocate_nothing
      expect(started).to eq(1)
    end
  end

  describe 'pushes:' do
    before do
      mount_collision_world
      add_box
    end

    it 'stops flush against a wall that is not Pushable, exactly as blocked_by alone does' do
      mover = enter_mover(blocked_by: [:wall], pushes: [:wall])
      reports = []
      mover.on_blocked { |by, axis| reports << [by, axis] }
      run_ticks(60)
      expect([mover_node.x, reports]).to eq([184.0, [[wall, :x]]])
    end

    # Fourteen steps reach the wall and the other forty-six push it, a pixel a step.
    it 'pushes a Pushable wall by what is left of each step, and follows it' do
      wall_node.add_component(RGame::Engine::Components::Pushable.new(blocked_by: []))
      enter_mover(blocked_by: [:wall], pushes: [:wall])
      run_ticks(60)
      expect([mover_node.x, wall_node.x]).to match([be_within(1e-6).of(230.0), be_within(1e-6).of(246.0)])
    end

    it 'allocates nothing on a step pressed into a wall it cannot push' do
      mover = enter_mover(blocked_by: [:wall], pushes: [:wall])
      run_ticks(60)
      expect { mover._update(mover_dt) }.to allocate_nothing
    end
  end

  # What an AnimatedSprite faces by. Compared by sign, because how long the heading is along
  # each axis is each mover's own business; which way it points is not.
  describe 'its heading' do
    def heading_signs(mover) = [mover.heading_x <=> 0, mover.heading_y <=> 0]

    [[1, 0], [0, 1], [1, 1]].each do |heading|
      it "points the way its step goes, for #{heading.inspect}" do
        mover = enter_mover(blocked_by: [], heading: heading)
        run_ticks(1)
        expect(heading_signs(mover)).to eq(heading)
      end
    end

    it 'stays within -1..1 on each axis' do
      mover = enter_mover(blocked_by: [], heading: [1, 1])
      run_ticks(1)
      expect([mover.heading_x, mover.heading_y]).to all(be_between(-1.0, 1.0))
    end

    it 'still heads into the wall it is pressed against' do
      mount_collision_world
      add_box
      mover = enter_mover(blocked_by: [:wall])
      run_ticks(60)
      expect(heading_signs(mover)).to eq([1, 0])
    end

    it 'allocates nothing to read' do
      mover = enter_mover(blocked_by: [])
      run_ticks(1)
      expect { mover.heading_x + mover.heading_y }.to allocate_nothing
    end
  end

  describe 'what it refuses at attach' do
    it 'refuses a declaration on a node with no BoxCollider' do
      mount_collision_world
      expect { enter_mover(blocked_by: [:wall]) }
        .to raise_error(/needs a RGame::Engine::Components::BoxCollider/)
    end

    it 'refuses a collider layer on a scene with no CollisionWorld, naming the mover and the layer' do
      add_box
      mover = build_mover(blocked_by: [:wall])
      name = mover.class.name.split('::').last
      expect { enter(mover) }.to raise_error(/#{name} is blocked_by :wall.*no CollisionWorld/m)
    end

    it 'refuses :gaps on a node with no Footing, naming the mover' do
      add_box
      mover_scene.add_component(
        RGame::Engine::Components::TileWorld.new(map: WalledTileMap.build(['..']), tilemap_id: :map)
      )
      mover = build_mover(blocked_by: [:gaps])
      name = mover.class.name.split('::').last
      expect { enter(mover) }.to raise_error(/#{name} is blocked_by :gaps, and its node has no Footing/)
    end

    it 'refuses :gaps on a scene with no TileWorld, naming the mover' do
      add_box
      mover = build_mover(blocked_by: [:gaps])
      name = mover.class.name.split('::').last
      expect { enter(mover) }.to raise_error(/#{name} is blocked_by :gaps, and the scene has no TileWorld/)
    end
  end
end
