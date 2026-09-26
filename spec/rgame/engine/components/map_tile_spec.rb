# frozen_string_literal: true

# A registered tile map that records the one tile each draw asks for, and draws
# it as the real one does, through image_at, so the renderer records the
# transforms and the z it was drawn under.
class SpecTileRecorder
  IMAGE = StubImage.new(16, 16)

  attr_reader :drawn

  def initialize = @drawn = []

  def draw_tile(renderer, tile, left, top, width, height, orientation, elapsed:, z:)
    @drawn << [[tile, left, top, width, height, orientation], { elapsed:, z: }]
    renderer.image_at(IMAGE, left, top, z:)
  end
end

# rubocop:disable RSpec/MultipleMemoizedHelpers -- a drawn tile needs its map, world, scene, renderer and orientation
RSpec.describe RGame::Engine::Components::MapTile do
  let(:tiles) { SpecTileRecorder.new }
  let(:renderer) { FakeRenderer.new.tap { it.register_tilemap('map/town.tmx', tiles) } }
  let(:world) do
    RGame::Engine::Components::TileWorld.new(map: StubTileMap.new(layers: [[1, 0, 0, 0]]), tilemap_id: 'map/town.tmx')
  end
  let(:scene) { RGame::Engine::Node2D.new.tap { it.add_component(world) } }
  let(:turned) { RGame::Engine::TileMap::Orientation::ALL[5] }

  # A 32x48 tile object at (100, 200) in the scene.
  def placed(x: 100, y: 200, width: 32, height: 48, **)
    node = scene.add_node(RGame::Engine::Node2D.new(x:, y:, width:, height:, **))
    node.add_component(described_class.new(tile: 5, orientation: turned))
    scene.enter_tree
    node
  end

  def draw(view = screen_view)
    scene.draw(renderer, view)
    tiles.drawn.last
  end

  it "draws its tile with its bottom centre on the node's origin, the node's size, under everything else" do
    placed

    expect(draw).to eq([[5, -16.0, -48, 32, 48, turned], { elapsed: 0.0, z: RGame::Util::Z::Z_MIN }])
  end

  it "passes no angle, since it draws inside its node's rotation" do
    placed(angle: Math::PI / 2)
    draw

    rotation = renderer.calls_to(:image_at).last.transforms.find { it.name == :rotated }
    expect(rotation.args).to eq([90.0, 0, 0])
  end

  it "is lifted by its node's elevation, as a sprite is" do
    placed.elevation = 9

    expect(draw.first[2]).to eq(-57)
  end

  it "animates on its TileWorld's clock, and stops when the world stops updating" do
    placed
    scene.update(0.25)

    expect(draw.last[:elapsed]).to eq(0.25)
  end

  it 'draws under a sprite its node added before it' do
    renderer.register_image(:chest, StubImage.new(32, 48))
    node = scene.add_node(RGame::Engine::Node2D.new(x: 100, y: 200, width: 32, height: 48))
    node.add_component(RGame::Engine::Components::Sprite.new(id: :chest))
    node.add_component(described_class.new(tile: 5))
    scene.enter_tree
    scene.draw(renderer, screen_view)

    expect(renderer.calls.sort_by(&:key).map(&:name).grep(/image/)).to eq(%i[image_at image])
  end

  it 'raises as it enters a tree with no TileWorld, naming it' do
    root = RGame::Engine::Node2D.new
    root.add_node(RGame::Engine::Node2D.new).add_component(described_class.new(tile: 5))

    expect { root.enter_tree }.to raise_error(KeyError, /TileWorld/)
  end

  # A world view 100x100 wide looking at (450, 450)..(550, 550).
  describe 'culling' do
    let(:camera) { RGame::Engine::Camera.new.center_on(500, 500).resolve(100, 100) }

    def drew?(x, y, width: 32, height: 48)
      placed(x:, y:, width:, height:)
      !draw(screen_view(width: 100, height: 100, camera:)).nil?
    end

    it 'draws a tile in view' do
      expect(drew?(500, 500)).to be(true)
    end

    it 'skips one well out of view' do
      expect(drew?(5000, 500)).to be(false)
    end

    # Its origin is 20px below the view, and its box stands 48px tall on it.
    it 'measures the box standing on its origin' do
      expect(drew?(500, 570)).to be(true)
    end

    it 'draws one whose node never set a size' do
      expect(drew?(5000, 5000, width: 0, height: 0)).to be(true)
    end
  end

  it 'allocates nothing to draw' do
    silent = Class.new do
      # rubocop:disable Lint/UnusedMethodArgument -- named keywords, since `**` would allocate a Hash per call
      def map_tile(_id, _tile, _left, _top, _width, _height, _orientation, elapsed: 0.0, z: 0) = nil
      # rubocop:enable Lint/UnusedMethodArgument
    end.new
    tile = placed.get_component(described_class)
    scene.update(0.0)
    view = screen_view

    expect { tile._draw(silent, view) }.to allocate_nothing
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
