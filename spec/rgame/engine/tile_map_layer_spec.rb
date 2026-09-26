# frozen_string_literal: true

# The classes a map in this file names, in a game's module as a game keeps them.
module SpecMountGame
  # The scene the maps are mounted in, and so where their classes resolve.
  class Scene < RGame::Engine::Node2D; end

  # A node that draws its object's name, so a spec can read where it drew.
  class Marker < RGame::Engine::Node2D
    def initialize(name:, **)
      super(**)
      @name = name
    end

    def _draw(renderer, _view) = renderer.text(@name, 0, 0)
  end
end

# rubocop:disable RSpec/MultipleMemoizedHelpers -- drawing a layer needs map, world, camera, renderer, scene, mount
RSpec.describe RGame::Engine::TileMapLayer do
  # Three layers, the last one flagged `above` — the shape both committed maps
  # have, and the one .mount reads to decide where the actors go.
  let(:map) do
    tile_map(tile_layer('layer0'), tile_layer('layer1', [0, 0, 0, 0]), tile_layer('layer2', [4, 0, 0, 0], above: true))
  end
  let(:world) { RGame::Engine::Components::TileWorld.new(map: map, tilemap_id: :level) }
  let(:camera) { RGame::Engine::Camera.new.center_on(500, 400) }
  let(:renderer) { instance_double(FakeRenderer, tilemap: nil, map_tile: nil, text: nil) }

  # The layers belong inside a WorldView, whose scene carries the TileWorld
  # system they read their map and clock from.
  let(:scene) { SpecMountGame::Scene.new.tap { |node| node.add_component(world) } }
  let(:mount) { described_class.mount(scene).tap { scene.enter_tree } }

  before do
    %i[layered translated rotated faded].each { allow(renderer).to receive(it).and_yield }
  end

  # Tile 4 of the tileset is a tree.
  def tileset
    '<tileset firstgid="1" name="terrain" tilewidth="16" tileheight="16" tilecount="4" columns="2">' \
      '<image source="terrain.png" width="32" height="32"/><tile id="3" type="tree"/></tileset>'
  end

  def tile_layer(name, gids = [1, 2, 0, 3], above: false)
    side = Integer.sqrt(gids.size)
    marks = above ? '<properties><property name="above" type="bool" value="true"/></properties>' : ''
    %(<layer name="#{name}" width="#{side}" height="#{side}">#{marks}#{TiledFixture.data(gids, encoding: :csv)}</layer>)
  end

  def object_layer(name, objects = '', attributes: '', actors: false)
    marks = actors ? '<properties><property name="actors" type="bool" value="true"/></properties>' : ''
    %(<objectgroup name="#{name}" #{attributes}>#{marks}#{objects}</objectgroup>)
  end

  # A point object of class Marker, which draws its name.
  def marker(id, name, y: 0) = %(<object id="#{id}" name="#{name}" type="Marker" x="0" y="#{y}"><point/></object>)

  def tile_map(*layers, size: 2)
    RGame::Engine::TileMap.from_tiled(RGame::Engine::Tiled::Map.parse(
                                        %(<map orientation="orthogonal" width="#{size}" height="#{size}" ) +
                                        %(tilewidth="16" tileheight="16">#{tileset}#{layers.join}</map>)
                                      ))
  end

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

  # The layer indices, the markers' names and the marks reached, in draw
  # order, with a node in each slot `marks` names drawing its mark.
  def drawn_with(marks)
    scene.enter_tree
    order = []
    allow(renderer).to receive(:tilemap) { |_id, layer, *| order << layer }
    allow(renderer).to receive(:text) { |name, *| order << name }
    marks.each do |slot, mark|
      marker = RGame::Engine::Node2D.new
      marker.define_singleton_method(:_draw) { |*| order << mark }
      slot.add_node(marker)
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

    it "returns the places, the actors' node among them" do
      actors = mount[:actors]

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
      let(:map) { tile_map(tile_layer('layer0'), tile_layer('layer1', [0, 0, 0, 0]), tile_layer('layer2')) }

      it 'puts the actors on top' do
        actors = mount[:actors]

        expect(scene.children.grep(described_class).map(&:z)).to all(be < actors.z)
      end
    end

    it "y-sorts the actors' node, so actors in it draw by where they stand" do
      expect(mount[:actors].y_sort).to be(true)
    end

    it "leaves the actors' node unsorted when told to, for a side-view game" do
      expect(described_class.mount(scene, y_sort: false)[:actors].y_sort).to be(false)
    end

    it 'takes no slots:, since object layers are the places' do
      expect { described_class.mount(scene, slots: { actors: nil }) }
        .to raise_error(ArgumentError, /unknown keyword: :slots/)
    end

    it 'raises for a second mount over the same TileWorld, naming its node' do
      mount

      expect { described_class.mount(scene) }
        .to raise_error(RuntimeError, /the map of SpecMountGame::Scene's TileWorld is already mounted/)
    end
  end

  # Object layers placed where a scene used to name a slot: one under a tile
  # layer, one over every layer, and one beside the actors under the canopy.
  describe 'places' do
    let(:map) do
      tile_map(tile_layer('layer0'), object_layer('boats'), tile_layer('layer1', [0, 0, 0, 0]),
               "<group name=\"Shade\">#{object_layer('shadows')}</group>",
               tile_layer('layer2', [4, 0, 0, 0], above: true), object_layer('sky'))
    end

    # The tile layers are 0, 2 and 4: an object layer takes an index too.
    it 'finds an object layer by its name, in its place among the layers' do
      expect(drawn_with(mount['boats'] => :boats, mount['sky'] => :sky)).to eq([0, :boats, 2, 4, :sky])
    end

    it "finds one by its 'Group/layer' path, as TileMap#layer_index takes it" do
      expect(mount['Shade/shadows']).to equal(mount['shadows'])
    end

    it 'draws an object layer under the canopy before the actors placed after it' do
      places = mount

      expect(drawn_with(places['shadows'] => :shadows, places[:actors] => :actors))
        .to eq([0, 2, :shadows, :actors, 4])
    end

    it "raises for a tile layer's name, saying only an object layer holds nodes" do
      expect { mount['layer1'] }
        .to raise_error(ArgumentError, %r{'layer1' is a tile layer, and only an object layer holds nodes.*Shade/})
    end

    it 'raises for a name no layer has, listing the object layers' do
      expect { mount['boots'] }
        .to raise_error(KeyError, %r{'boots' names no one layer of this map.*boats, Shade/shadows, sky})
    end

    it 'raises for any other key' do
      expect { mount[:boats] }.to raise_error(ArgumentError, /a place is :actors, or the name.*got :boats/)
    end
  end

  describe 'an object layer' do
    let(:map) do
      tile_map(tile_layer('ground'), object_layer('things', marker(1, 'north', y: 4) + marker(2, 'south', y: 12)),
               tile_layer('canopy', [4, 0, 0, 0], above: true))
    end

    def things = mount['things']

    it 'is a node in its place among the layers, holding what its objects build' do
      expect(drawn_with(mount[:actors] => :actors)).to eq([0, 'north', 'south', :actors, 2])
    end

    it 'builds its objects in the order the layer lists them, and adds them under it' do
      expect(things.children.map(&:map_object_id)).to eq([1, 2])
    end

    it 'resolves their classes in the class of the node the TileWorld is attached to' do
      expect(things.children).to all(be_a(SpecMountGame::Marker))
    end

    it 'y-sorts a layer Tiled draws Top Down' do
      expect(things.y_sort).to be(true)
    end

    context 'when Tiled draws it Manual' do
      let(:map) do
        tile_map(tile_layer('ground'), object_layer('things', marker(1, 'south', y: 12) + marker(2, 'north', y: 4),
                                                    attributes: 'draworder="index"'))
      end

      it "keeps Tiled's order" do
        expect([things.y_sort, drawn_with({})]).to eq([false, [0, 'south', 'north']])
      end
    end

    context 'when the layer is translucent' do
      let(:map) do
        tile_map(tile_layer('ground'), object_layer('things', marker(1, 'north'), attributes: 'opacity="0.5"'))
      end

      it "draws at the layer's opacity" do
        expect(things.opacity).to eq(0.5)
      end
    end

    context 'when the layer is hidden' do
      let(:map) do
        tile_map(tile_layer('ground'), object_layer('things', marker(1, 'north'), attributes: 'visible="0"'))
      end

      it 'builds its objects, and draws none of them' do
        expect([things.children.size, things.opacity, drawn_with({})]).to eq([1, 0, [0]])
      end
    end

    context 'when it holds a tile object' do
      let(:map) do
        tile_map(tile_layer('ground'),
                 object_layer('things', '<object id="3" gid="4" x="0" y="16" width="16" height="16"/>'))
      end

      it 'draws its tile' do
        mount
        allow(renderer).to receive(:map_tile)
        scene.draw(renderer, view)

        expect(renderer).to have_received(:map_tile).with(:level, 4, -8.0, -16.0, 16.0, 16.0, any_args)
      end
    end
  end

  describe 'the actors mark' do
    let(:map) do
      tile_map(tile_layer('ground'), object_layer('spawns', marker(1, 'north'), actors: true),
               tile_layer('canopy', [4, 0, 0, 0], above: true))
    end

    it "makes the marked layer the actors' place" do
      places = mount

      expect([places[:actors], places[:actors].children.map(&:map_object_id)]).to eq([places['spawns'], [1]])
    end

    it 'draws the actors among its objects, under the canopy' do
      expect(drawn_with(mount[:actors] => :actors)).to eq([0, 'north', :actors, 2])
    end

    it 'leaves no node of its own for the actors' do
      mount

      expect(scene.children.size).to eq(3)
    end
  end

  # The caller that uses all of it: a tree placed in Tiled as a tile object of
  # the data class `tree`, in the layer marked for the actors, under a canopy.
  # A hero the scene spawns sorts against the tree in both halves of a split
  # screen, as one actor sorts against another.
  describe 'a hero walking past a tree placed in Tiled, in two views' do
    let(:map) do
      tree = '<object id="5" gid="4" x="16" y="48" width="16" height="32"/>'
      tile_map(tile_layer('ground', [1] * 16), object_layer('trees', tree, actors: true),
               tile_layer('canopy', [0] * 15 + [4], above: true), size: 4)
    end
    let(:players) { RGame::Engine::Players.new([player(0), player(1)]) }
    let(:viewports) { RGame::Engine::Viewports.new(players, width: 640, height: 480) }
    let(:hero) { RGame::Engine::Node2D.new(x: 24) }

    before do
      scene.add_component(players)
      scene.add_component(viewports)
      described_class.mount(scene.add_node(RGame::Engine::WorldView.new))[:actors].add_node(hero)
      viewports.refresh
      scene.enter_tree
    end

    def player(id) = RGame::Engine::Player.new(id: id, device: RGame::Util::Controls.gamepad(id))

    # What each view drew, in order: a layer by its index, the tree's tile and
    # the hero.
    def drawn
      order = []
      allow(renderer).to receive(:clipped).and_yield
      allow(renderer).to receive(:tilemap) { |_id, layer, *| order << layer }
      allow(renderer).to receive(:map_tile) { order << :tree }
      hero.define_singleton_method(:_draw) { |*| order << :hero }
      scene.draw(renderer, viewports.screen)
      order
    end

    it "draws the hero behind the tree while standing north of the tree's origin" do
      hero.y = 40

      expect(drawn).to eq([0, :hero, :tree, 2] * 2)
    end

    it 'draws the hero in front of the tree once south of it' do
      hero.y = 56

      expect(drawn).to eq([0, :tree, :hero, 2] * 2)
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
