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

  def platform_at(x, y, width: 32)
    node = engine::Node2D.new(x: x, y: y)
    node.add_component(parts::BoxCollider.new(width: width, height: 16, offset_x: -width / 2.0, offset_y: -8))
    platform = node.add_component(described_class.new)
    root.add_node(node)
    root.enter_tree
    platform
  end

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
