# frozen_string_literal: true

# rubocop:disable RSpec/MultipleMemoizedHelpers -- drawing a layer needs map, world, camera, renderer, scene, mount
RSpec.describe RGame::Engine::TileMapLayer do
  # Three layers, the last one flagged `above` — the shape both committed maps
  # have, and the one .mount reads to decide where the actors go.
  let(:map) do
    StubTileMap.new(layers: [[1, 2, 0, 3], [0, 0, 0, 0], [4, 0, 0, 0]],
                    above: [false, false, true])
  end
  let(:world) { RGame::Engine::Components::TileWorld.new(map: map, tilemap_id: :level) }
  let(:camera) { RGame::Engine::Camera.new.center_on(500, 400) }
  let(:renderer) { instance_double(FakeRenderer, tilemap: nil, layered: nil) }

  # The layers belong inside a WorldView, whose scene carries the TileWorld
  # system they read their map and clock from.
  let(:scene) { RGame::Engine::Node2D.new.tap { |node| node.add_component(world) } }
  let(:mount) { described_class.mount(scene).tap { scene.enter_tree } }

  before { allow(renderer).to receive(:layered).and_yield }

  def view(width: 320, height: 240) = screen_view(width: width, height: height, camera: camera)

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

  # The layer indices and marks reached, in draw order, with a node in each
  # gap `marks` names drawing its mark.
  def drawn_with(marks)
    scene.enter_tree
    order = []
    allow(renderer).to receive(:tilemap) { |_id, layer, *| order << layer }
    marks.each do |gap, mark|
      marker = RGame::Engine::Node2D.new
      marker.define_singleton_method(:_draw) { |*| order << mark }
      gap.add_node(marker)
    end
    scene.draw(renderer, view)
    order
  end

  describe '.mount' do
    it 'mounts one node per layer of the map' do
      mount

      expect(scene.children.grep(described_class).size).to eq(3)
    end

    it 'draws them in the order Tiled lists them' do
      expect(drawn_layers).to eq([0, 1, 2])
    end

    it 'returns the gaps as slots, with one for the actors' do
      actors = mount[:actors]

      expect(mount.names).to eq([:actors])
      expect(actors).to be_a(RGame::Engine::Node2D)
      expect(actors).not_to be_a(described_class)
      expect(scene.children).to include(actors)
    end

    it "puts the actors' node under the first layer flagged above" do
      actors = mount[:actors]
      layers = scene.children.grep(described_class)

      # Layers 0 and 1 sort before the actors; the flagged layer 2 sorts after.
      expect(layers.map { |layer| layer.z < actors.z }).to eq([true, true, false])
    end

    it 'draws the actors between the layers they belong between' do
      expect(drawn_with(mount[:actors] => :actors)).to eq([0, 1, :actors, 2])
    end

    context 'when the map flags no layer above' do
      let(:map) { StubTileMap.new(layers: [[1, 2, 0, 3], [0, 0, 0, 0], [4, 0, 0, 0]]) }

      it 'puts the actors on top' do
        actors = mount[:actors]

        expect(scene.children.grep(described_class).map(&:z)).to all(be < actors.z)
      end
    end

    it 'puts a gap under the layer an index names' do
      slots = described_class.mount(scene, gaps: { actors: 1 })

      expect(drawn_with(slots[:actors] => :actors)).to eq([0, :actors, 1, 2])
    end

    it 'puts a gap under the layer a name names' do
      slots = described_class.mount(scene, gaps: { boats: 'layer1' })

      expect(drawn_with(slots[:boats] => :boats)).to eq([0, :boats, 1, 2])
    end

    it 'puts a gap over every layer at layer_count' do
      slots = described_class.mount(scene, gaps: { sky: 3 })

      expect(drawn_with(slots[:sky] => :sky)).to eq([0, 1, 2, :sky])
    end

    it 'draws two gaps under one layer in the order they were declared' do
      slots = described_class.mount(scene, gaps: { shadows: nil, actors: nil, boats: 1 })

      expect(slots.names).to eq(%i[shadows actors boats])
      expect(drawn_with(slots[:shadows] => :shadows, slots[:actors] => :actors, slots[:boats] => :boats))
        .to eq([0, :boats, 1, :shadows, :actors, 2])
    end

    it 'y-sorts every gap, so actors in one draw by where they stand' do
      slots = described_class.mount(scene, gaps: { shadows: nil, actors: nil })

      expect(slots.names.map { slots[it].y_sort }).to all(be(true))
    end

    it 'leaves the gaps unsorted when told to, for a side-view game' do
      slots = described_class.mount(scene, gaps: { shadows: nil, actors: nil }, y_sort: false)

      expect(slots.names.map { slots[it].y_sort }).to all(be(false))
    end

    it 'raises at mount for a layer name the map lacks, listing its layers' do
      expect { described_class.mount(scene, gaps: { actors: 'canopy' }) }
        .to raise_error(KeyError, /no layer 'canopy'.*layer0, layer1, layer2/)
    end

    it 'raises for a layer index past the last' do
      expect { described_class.mount(scene, gaps: { actors: 4 }) }
        .to raise_error(ArgumentError, /from 0 to 3.*got 4/)
    end

    it 'raises naming the gaps for a slot that was not mounted' do
      expect { mount[:actorz] }.to raise_error(KeyError, /no gap :actorz was mounted \(the gaps are :actors\)/)
    end

    context 'when a layer is an object layer' do
      let(:map) do
        StubTileMap.new(layers: [[1, 2, 0, 3], nil, [4, 0, 0, 0]], object_layers: [1], above: [false, false, true])
      end

      it 'mounts no node for it, and draws the others' do
        expect(drawn_with(mount[:actors] => :actors)).to eq([0, :actors, 2])
      end
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
      3.times { world._update(0.5) }
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
# rubocop:enable RSpec/MultipleMemoizedHelpers
