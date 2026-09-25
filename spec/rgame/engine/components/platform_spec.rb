# frozen_string_literal: true

# A chasm six tiles wide, columns 3 to 8 (x 48 to 144) of every row, and platforms over
# it: 32 by 16 boxes centred on their node.
RSpec.describe RGame::Engine::Components::Platform do
  let(:root) do
    engine::Node2D.new.tap do |scene|
      scene.scene = scene
      map = WalledTileMap.build(Array.new(4) { '...~~~~~~...' })
      scene.add_component(parts::TileWorld.new(map: map, tilemap_id: :map))
    end
  end
  let(:world) { root.get_component(parts::TileWorld) }

  def engine = RGame::Engine
  def parts = RGame::Engine::Components

  def platform_at(x, y, width: 32, vx: nil)
    node = engine::Node2D.new(x: x, y: y)
    node.add_component(parts::BoxCollider.new(width: width, height: 16, offset_x: -width / 2.0, offset_y: -8,
                                              layer: :platform))
    platform = node.add_component(described_class.new)
    node.add_component(parts::Velocity.new(vx: vx)) if vx
    root.add_node(node)
    root.enter_tree
    platform
  end

  # An 8x8 box centred on the node, so the node stands where its box's centre is.
  def rider_at(x, y, body: true, blocked_by: [], hop: false)
    node = engine::Node2D.new(x: x, y: y)
    node.add_component(parts::BoxCollider.new(width: 8, height: 8, offset_x: -4, offset_y: -4, layer: :rider))
    node.add_component(parts::Footing.new)
    node.add_component(parts::CharacterBody.new(speed: 60, blocked_by:)) if body
    node.add_component(parts::Hop.new(peak: 10, duration: 0.5, action: nil)) if hop
    root.add_node(node)
    root.enter_tree
    node
  end

  def footing(node) = node.get_component(parts::Footing)
  def dt = 1.0 / 60

  def tick
    root.update(dt)
    root.sweep_freed
  end

  def ticks(count) = count.times { tick }

  describe 'attaching' do
    it 'raises without a BoxCollider on the node' do
      root.add_node(engine::Node2D.new.tap { it.add_component(described_class.new) })
      expect { root.enter_tree }.to raise_error(RuntimeError, /BoxCollider/)
    end

    it 'raises without a TileWorld on the scene' do
      bare = engine::Node2D.new.tap { it.scene = it }
      node = engine::Node2D.new
      node.add_component(parts::BoxCollider.new(width: 32, height: 16))
      node.add_component(described_class.new)
      bare.add_node(node)
      expect { bare.enter_tree }.to raise_error(RuntimeError, /TileWorld/)
    end
  end

  describe '#covers?' do
    it 'covers its box, its left and top edges included and its right and bottom edges not' do
      platform = platform_at(80.0, 24.0) # box 64..96 by 16..32
      expect([platform.covers?(64.0, 16.0), platform.covers?(95.9, 31.9),
              platform.covers?(96.0, 20.0), platform.covers?(70.0, 32.0)]).to eq([true, true, false, false])
    end

    it 'names its edges in world pixels' do
      platform = platform_at(80.0, 24.0)
      expect([platform.left, platform.top, platform.right, platform.bottom]).to eq([64.0, 16.0, 96.0, 32.0])
    end
  end

  describe 'the floor over a gap' do
    it 'is floor where the box covers a gap, and a gap beside it' do
      platform_at(80.0, 24.0)
      expect([world.floor_at?(70.0, 24.0), world.floor_at?(100.0, 24.0), world.floor_at?(70.0, 40.0)])
        .to eq([true, false, false])
    end

    it 'is not ground where the box covers a gap' do
      platform_at(80.0, 24.0)
      expect([world.floor_at?(70.0, 24.0), world.ground_at?(70.0, 24.0), world.ground_at?(40.0, 24.0)])
        .to eq([true, false, true])
    end

    it 'is the platform a point over the gap stands on' do
      platform = platform_at(80.0, 24.0)
      expect([world.platform_under(70.0, 24.0), world.platform_under(100.0, 24.0)]).to eq([platform, nil])
    end

    it 'is nobody’s platform where the cell is ground, though the box covers it' do
      platform = platform_at(48.0, 24.0) # box 32..64: ground to 48, gap after
      expect([world.platform_under(40.0, 24.0), world.platform_under(50.0, 24.0)]).to eq([nil, platform])
    end

    it 'is the first platform registered, where two cover a point' do
      first = platform_at(80.0, 24.0)
      platform_at(90.0, 24.0)
      expect(world.platform_under(90.0, 24.0)).to be(first)
    end

    it 'moves with the platform' do
      platform = platform_at(80.0, 24.0)
      platform.node.x = 120.0
      expect([world.floor_at?(70.0, 24.0), world.floor_at?(110.0, 24.0)]).to eq([false, true])
    end

    it 'is a gap again once the platform leaves the tree' do
      platform = platform_at(80.0, 24.0)
      platform.node.queue_free
      root.sweep_freed
      expect([world.floor_at?(70.0, 24.0), world.platform_under(70.0, 24.0)]).to eq([false, nil])
    end

    it 'refuses a platform registered twice' do
      platform = platform_at(80.0, 24.0)
      expect { world.bridge(platform) }.to raise_error(ArgumentError, /already/)
    end
  end

  describe 'riding' do
    it 'boards the platform under the centre of a node over a gap' do
      platform = platform_at(80.0, 24.0)
      node = rider_at(70.0, 24.0)
      tick
      expect([footing(node).platform, platform.riders]).to eq([platform, [footing(node)]])
    end

    # The platform updates before the rider, so the rider boards at the end of the first
    # tick and is carried from the second.
    it 'rides in the air too' do
      platform = platform_at(80.0, 24.0, vx: 60)
      node = rider_at(80.0, 24.0, hop: true)
      node.get_component(parts::Hop).jump
      tick
      ticks(10)
      expect([footing(node).platform, node.x - platform.node.x]).to match([platform, be_within(1e-9).of(-1.0)])
    end

    it 'does not ride where the ground is under it, though the box covers it' do
      platform = platform_at(48.0, 24.0, vx: 60) # box 32..64: ground to 48
      node = rider_at(40.0, 24.0)
      tick
      expect([footing(node).platform, platform.riders, node.x]).to eq([nil, [], 40.0])
    end

    it 'carries a rider with no Mover straight by its step' do
      platform = platform_at(80.0, 24.0, vx: 60)
      node = rider_at(76.0, 24.0, body: false)
      tick
      ticks(20)
      expect(node.x - platform.node.x).to be_within(1e-9).of(-5.0)
    end

    it 'leaves the platform as the node steps off it onto the ground' do
      platform = platform_at(64.0, 24.0) # box 48..80, flush with the ground's edge at 48
      node = rider_at(52.0, 24.0)
      tick
      node.get_component(parts::CharacterBody).set_intent(-1, 0)
      ticks(10)
      expect([footing(node).platform, platform.riders]).to eq([nil, []])
    end
  end

  # A 48 px platform under two riders, flush against each other and each blocked by the
  # other, so a carry that moved the one behind first would leave it where it was.
  describe 'riders flush against each other' do
    before { root.add_component(parts::CollisionWorld.new(cell_size: 64)) }

    [[:front, 60], [:front, -60], [:back, 60], [:back, -60]].each do |first, vx|
      it "stay flush, with the #{first} one aboard first, carried at #{vx} px/s" do
        platform_at(96.0, 24.0, width: 48, vx: vx)
        ahead_x, behind_x = vx.positive? ? [98.0, 90.0] : [90.0, 98.0]
        order = first == :front ? [ahead_x, behind_x] : [behind_x, ahead_x]
        riders = order.map { rider_at(it, 24.0, blocked_by: [:rider]) }
        ticks(20)
        expect((riders[0].x - riders[1].x).abs).to be_within(1e-9).of(8.0)
      end
    end
  end

  # A wall standing in the chasm, its left edge at x = 120, that stops a rider and not
  # the platform carrying it.
  describe 'a wall in the way' do
    before do
      root.add_component(parts::CollisionWorld.new(cell_size: 64))
      wall = engine::Node2D.new(x: 120.0, y: 0.0)
      wall.add_component(parts::BoxCollider.new(width: 8, height: 64, layer: :wall))
      root.add_node(wall)
    end

    it 'stops the rider and not the platform, and the rider falls once it is off' do
      platform = platform_at(80.0, 24.0, width: 48, vx: 60)
      node = rider_at(80.0, 24.0, blocked_by: [:wall])
      ticks(80)
      expect([node.x, platform.node.x, footing(node).falling?]).to match([116.0, be_within(1e-9).of(160.0), true])
    end
  end

  describe 'leaving the tree' do
    it 'lets every rider go as the platform leaves' do
      platform = platform_at(80.0, 24.0)
      node = rider_at(80.0, 24.0)
      tick
      platform.node.queue_free
      root.sweep_freed
      expect([footing(node).platform, platform.riders]).to eq([nil, []])
    end

    it 'leaves the platform as the rider leaves' do
      platform = platform_at(80.0, 24.0)
      node = rider_at(80.0, 24.0)
      tick
      node.queue_free
      root.sweep_freed
      expect(platform.riders).to eq([])
    end
  end

  describe 'how far the floor reaches' do
    it 'goes on from the ground onto a platform that meets it' do
      platform_at(64.0, 24.0) # box 48..80, flush with the ground's edge
      expect(world.floor_reach_x(40.0, 24.0, 30.0)).to eq(30.0)
    end

    it 'stops a point on a platform short of its far edge' do
      platform_at(64.0, 24.0)
      reach = world.floor_reach_x(60.0, 24.0, 40.0)
      expect([reach, world.floor_at?(60.0 + reach, 24.0)]).to match([be_within(1e-6).of(20.0), true])
    end

    it 'stops a point moving left on a platform short of its near edge' do
      platform_at(96.0, 24.0) # box 80..112
      reach = world.floor_reach_x(100.0, 24.0, -40.0)
      expect([reach, world.floor_at?(100.0 + reach, 24.0)]).to match([be_within(1e-6).of(-20.0), true])
    end

    it 'goes on across two platforms that touch, and onto the ground beyond' do
      platform_at(64.0, 24.0, width: 32) # 48..80
      platform_at(112.0, 24.0, width: 64) # 80..144, flush with the far bank
      expect([world.floor_reach_x(40.0, 24.0, 120.0), world.floor_reach_x(150.0, 24.0, -120.0)]).to eq([120.0, -120.0])
    end

    it 'stops at a gap between two platforms' do
      platform_at(64.0, 24.0) # 48..80
      platform_at(100.0, 24.0) # 84..116
      expect(world.floor_reach_x(40.0, 24.0, 60.0)).to be_within(1e-6).of(40.0)
    end

    it 'stops a point moving down on a platform short of its bottom edge' do
      platform_at(80.0, 24.0) # 16..32
      reach = world.floor_reach_y(70.0, 20.0, 30.0)
      expect([reach, world.floor_at?(70.0, 20.0 + reach)]).to match([be_within(1e-6).of(12.0), true])
    end

    it 'goes on up and down across platforms stacked edge to edge' do
      platform_at(80.0, 24.0) # 16..32
      platform_at(80.0, 40.0) # 32..48
      expect([world.floor_reach_y(70.0, 20.0, 25.0), world.floor_reach_y(70.0, 45.0, -25.0)]).to eq([25.0, -25.0])
    end
  end
end
