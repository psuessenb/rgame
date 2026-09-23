# frozen_string_literal: true

RSpec.describe RGame::Engine::WorldView do
  def player(id)
    RGame::Engine::Player.new(id: id, device: RGame::Util::Controls.gamepad(id))
  end

  let(:players)   { RGame::Engine::Players.new([player(0), player(1)]) }
  let(:viewports) { RGame::Engine::Viewports.new(players, width: 640, height: 480) }
  let(:renderer)  { FakeRenderer.new }

  # A world view is always mounted in a tree, because it asks the tree which
  # viewports exist rather than being told.
  let(:root) do
    RGame::Engine::Node2D.new.tap do |node|
      node.add_component(players)
      node.add_component(viewports)
    end
  end

  let(:world) { root.add_node(described_class.new) }

  before do
    players.each { |p| p.camera.center_on(1000, 1000) }
    viewports.refresh
    world # mount it
  end

  # Driven from the root, the way the platform does: a node resolves its origin
  # from its parent's, so the parent has to have been resolved first.
  def draw_frame = root.draw(renderer, viewports.screen)

  describe 'drawing once per viewport' do
    it 'clips to each viewport in turn' do
      world.add_node(RGame::Engine::Node2D.new)
      draw_frame

      expect(renderer.calls_to(:clipped).map(&:args))
        .to eq([[0, 0, 640, 240], [0, 240, 640, 240]])
    end

    it 'translates by each viewport\'s own camera offset' do
      draw_frame

      offsets = viewports.views.map { |v| [v.offset_x, v.offset_y] }
      expect(renderer.calls_to(:translated).map(&:args)).to eq(offsets)
    end

    it 'draws its subtree once per viewport' do
      drawn = 0
      child = world.add_node(RGame::Engine::Node2D.new)
      allow(child).to receive(:draw) { drawn += 1 }

      draw_frame

      expect(drawn).to eq(2)
    end

    it 'hands each pass the view it is drawing into' do
      seen = []
      child = world.add_node(RGame::Engine::Node2D.new)
      allow(child).to receive(:draw) { |_r, view| seen << view }

      draw_frame

      expect(seen).to eq(viewports.views)
    end

    # It overrides the whole of draw rather than only draw_children, so its own
    # visuals land inside the viewport too rather than once outside all of them.
    it 'draws its own content inside the viewports, not outside them' do
      component = RGame::Engine::Component.new
      seen = []
      allow(component).to receive(:_draw) { |_r, view| seen << view }
      world.add_component(component)

      draw_frame

      expect(seen).to eq(viewports.views)
    end
  end

  describe 'with one viewport' do
    let(:players) { RGame::Engine::Players.new([player(0)]) }

    it 'draws the subtree exactly once' do
      drawn = 0
      child = world.add_node(RGame::Engine::Node2D.new)
      allow(child).to receive(:draw) { drawn += 1 }

      draw_frame

      expect(drawn).to eq(1)
    end
  end

  # The invariant the whole design rests on: the simulation is shared, only the
  # drawing multiplies. An NPC that moved twice as fast with two players
  # watching would be the classic way to get this wrong.
  # rubocop:disable RSpec/MultipleMemoizedHelpers -- one shared world, its viewports, and the node counting ticks
  describe 'the simulation is not multiplied' do
    let(:counter) do
      Class.new(RGame::Engine::Node2D) do
        attr_reader :updates, :controls, :draws

        def initialize
          super
          @updates = @controls = @draws = 0
        end

        def _update(_dt) = @updates += 1
        def _control(_actions) = @controls += 1
        def _draw(_renderer, _view) = @draws += 1
      end.new
    end

    before do
      world.add_node(counter)
      players.poll(FakeInputBackend.new, 0.016)
      root.control(players)
      root.update(0.016)
      draw_frame
    end

    it 'updates a world node once, however many players are watching' do
      expect(counter.updates).to eq(1)
    end

    it 'controls it once' do
      expect(counter.controls).to eq(1)
    end

    it 'draws it once per viewport' do
      expect(counter.draws).to eq(2)
    end
  end
  # rubocop:enable RSpec/MultipleMemoizedHelpers

  # The node already drawing once per viewport in world space is the one that
  # draws the map's solid cells, so they follow each camera with nothing
  # mounted and no arithmetic of their own.
  # rubocop:disable RSpec/MultipleMemoizedHelpers -- the shared world, its viewports, the debug layer and the map
  describe 'the debug layer\'s solid cells' do
    let(:players) { RGame::Engine::Players.new([player(0)]) }
    let(:debug) { RGame::Engine::Debug.new }
    let(:map) { WalledTileMap.build(['....', '.##.', '....']) }

    let(:root) do
      RGame::Engine::Node2D.new.tap do |node|
        node.add_component(players)
        node.add_component(viewports)
        node.add_component(debug)
      end
    end

    # Marked as a scene boundary the way SceneStack#push marks one, since a
    # TileWorld is scene-scoped and `system` looks at the scene before the root.
    let(:scene) do
      root.add_node(RGame::Engine::Node2D.new).tap do |node|
        node.scene = node
        node.add_component(RGame::Engine::Components::TileWorld.new(map: map, tilemap_id: 'walls.tmx'))
      end
    end

    let(:world) { scene.add_node(described_class.new) }

    before do
      players.primary.camera.center_on(32, 24)
      viewports.refresh
      root.enter_tree
    end

    it 'draws a box over each solid cell in view' do
      debug.show(:shapes)

      draw_frame

      expect(renderer.calls_to(:debug_box).map(&:args)).to eq([[16, 16, 16, 16], [32, 16, 16, 16]])
    end

    it 'draws nothing while the channel is off' do
      draw_frame

      expect(renderer.drawn?(:debug_box)).to be(false)
    end

    it 'draws a cell something occupies, as the map counts it solid' do
      scene.get_component(RGame::Engine::Components::TileWorld).occupy(0, 0)
      debug.show(:shapes)

      draw_frame

      expect(renderer.calls_to(:debug_box).map(&:args)).to include([0, 0, 16, 16])
    end

    it 'draws in the debug band, over the world it covers' do
      debug.show(:shapes)

      draw_frame

      expect(renderer.calls_to(:debug_box).map(&:layer))
        .to all(be >= RGame::Util::Z.base(:debug, 0))
    end

    it 'draws the cells once per viewport' do
      players.list << RGame::Engine::Player.new(id: 1, device: RGame::Util::Controls.gamepad(1))
      viewports.refresh
      debug.show(:shapes)

      draw_frame

      expect(renderer.calls_to(:debug_box).count).to eq(4)
    end

    describe 'in a scene with no tile world' do
      let(:scene) { root.add_node(RGame::Engine::Node2D.new).tap { it.scene = it } }

      it 'draws nothing' do
        debug.show(:shapes)

        draw_frame

        expect(renderer.drawn?(:debug_box)).to be(false)
      end
    end
  end
  # rubocop:enable RSpec/MultipleMemoizedHelpers
end
