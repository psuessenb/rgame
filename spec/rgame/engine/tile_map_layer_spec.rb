# frozen_string_literal: true

RSpec.describe RGame::Engine::TileMapLayer do
  # Three layers, the last one flagged `above` — the shape both committed maps
  # have, and the one .mount reads to decide where the actors go.
  let(:map) do
    StubTileMap.new(layers: [[1, 2, 0, 3], [0, 0, 0, 0], [4, 0, 0, 0]],
                    above: [false, false, true], tileset: StubTileset.new)
  end
  let(:world) { RGame::Engine::Components::TileWorld.new(map: map, tilemap_id: :level) }
  let(:camera) { RGame::Engine::Camera.new.center_on(500, 400) }
  let(:renderer) { instance_double(FakeRenderer, tilemap: nil, layered: nil) }

  # The layers belong inside a WorldView, whose scene carries the TileWorld
  # system they read their map and clock from.
  let(:scene) { RGame::Engine::Node2D.new.tap { |node| node.add_component(world) } }

  before { allow(renderer).to receive(:layered).and_yield }

  def view(width: 320, height: 240) = screen_view(width: width, height: height, camera: camera)

  def mount = @mount ||= described_class.mount(scene).tap { scene.enter_tree }

  # Driven from the scene, the way the traversal does: a node resolves its
  # origin from its parent's, so the parent has to have been resolved first.
  def draw_frame(into = view)
    mount
    scene.draw(renderer, into)
  end

  # Which layer indices reached the renderer, in the order they were drawn.
  def drawn_layers
    calls = []
    allow(renderer).to receive(:tilemap) { |_id, layer, *| calls << layer }
    draw_frame
    calls
  end

  describe '.mount' do
    it 'mounts one node per layer of the map' do
      mount

      expect(scene.children.grep(described_class).size).to eq(3)
    end

    it 'draws them in the order Tiled lists them' do
      expect(drawn_layers).to eq([0, 1, 2])
    end

    it 'returns a node for the actors, in the gap' do
      actors = mount

      expect(actors).to be_a(RGame::Engine::Node2D)
      expect(actors).not_to be_a(described_class)
      expect(scene.children).to include(actors)
    end

    it "puts the actors' node under the first layer flagged above" do
      actors = mount
      layers = scene.children.grep(described_class)

      # Layers 0 and 1 sort before the actors; the flagged layer 2 sorts after.
      expect(layers.map { |layer| layer.z < actors.z }).to eq([true, true, false])
    end

    it 'draws the actors between the layers they belong between' do
      actors = mount
      order = []
      allow(renderer).to receive(:tilemap) { |_id, layer, *| order << layer }
      actors.add_node(RGame::Engine::Node2D.new.tap do |node|
        node.define_singleton_method(:on_draw) { |*| order << :actors }
      end)

      scene.draw(renderer, view)

      expect(order).to eq([0, 1, :actors, 2])
    end

    it 'puts the actors on top when the map flags no layer above' do
      allow(map).to receive(:above_layer?).and_return(false)
      actors = mount

      expect(scene.children.grep(described_class).map(&:z)).to all(be < actors.z)
    end

    it 'takes an explicit layer to slip under, for a map that wants a different gap' do
      actors = described_class.mount(scene, under: 1)

      layers = scene.children.grep(described_class)
      expect(layers[0].z).to be < actors.z
      expect(layers[1].z).to be > actors.z
    end
  end

  describe 'drawing' do
    it "names the map the scene's TileWorld holds" do
      draw_frame

      expect(renderer).to have_received(:tilemap).with(:level, any_args).at_least(:once)
    end

    it 'draws an empty layer like any other — it replays as nothing' do
      # Layer 1 has no tiles at all. Skipping it here would shift every index
      # after it, so the emptiness is the recording's problem, not this node's.
      expect(drawn_layers).to include(1)
    end
  end

  describe 'the cull rect' do
    # It passes the camera through as the region worth drawing, and does no
    # arithmetic of its own — the map draws in world coordinates and the
    # WorldView's translate is what puts it on screen. That is exactly what
    # lets the same map serve every viewport.
    it "is the camera's position and the view's size" do
      camera.resolve(320, 240)
      draw_frame

      expect(renderer).to have_received(:tilemap)
        .with(:level, 0, camera.x, camera.y, 320, 240, any_args)
    end

    it 'follows the view, so two viewports cull differently' do
      other = RGame::Engine::Camera.new.center_on(2000, 2000).resolve(100, 100)
      draw_frame(screen_view(width: 100, height: 100, camera: other))

      expect(renderer).to have_received(:tilemap)
        .with(:level, 0, other.x, other.y, 100, 100, any_args)
    end
  end

  describe 'the animation clock' do
    it "hands the scene's elapsed seconds to every layer" do
      3.times { world.update(0.5) }
      draw_frame

      expect(renderer).to have_received(:tilemap)
        .with(any_args, hash_including(elapsed: 1.5)).exactly(3).times
    end
  end

  # A screen-space band has no camera and so nothing to cull against. That is a
  # misplaced layer rather than a state to cope with, and saying so beats
  # drawing the map at the origin of every HUD.
  it 'refuses to draw outside a world view' do
    expect { draw_frame(screen_view) }
      .to raise_error(/must be inside a WorldView/)
  end
end
