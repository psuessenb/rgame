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
      allow(component).to receive(:draw) { |_r, view| seen << view }
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
  describe 'the simulation is not multiplied' do
    def counter
      @counter ||= Class.new(RGame::Engine::Node2D) do
        attr_reader :updates, :controls, :draws

        def initialize
          super
          @updates = @controls = @draws = 0
        end

        def on_update(_dt) = @updates += 1
        def on_control(_actions) = @controls += 1
        def on_draw(_renderer, _view) = @draws += 1
      end.new
    end

    before do
      world.add_node(counter)
      players.poll(FakeInputBackend.new)
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
end
