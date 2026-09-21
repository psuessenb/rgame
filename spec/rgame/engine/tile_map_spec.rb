# frozen_string_literal: true

# The runtime view, built the only way one is built: parse a `.tmx` string with
# its tilesets embedded, then `from_tiled`. No file is touched from end to end,
# which is what keeps a map spec-able headless.
RSpec.describe RGame::Engine::TileMap do
  let(:tiled) { RGame::Engine::Tiled }
  let(:solid_shape) { '<objectgroup><object x="0" y="0" width="16" height="16"/></objectgroup>' }

  def sheet(firstgid: 1, name: 'terrain', count: 4, tiles: '')
    %(<tileset firstgid="#{firstgid}" name="#{name}" tilewidth="16" tileheight="16" ) +
      %(tilecount="#{count}" columns="2"><image source="#{name}.png" width="32" height="32"/>#{tiles}</tileset>)
  end

  def layer(gids, name: 'ground', width: 2, height: 2, attributes: '', properties: '')
    %(<layer name="#{name}" width="#{width}" height="#{height}" #{attributes}>#{properties}) +
      "#{TiledFixture.data(gids, encoding: :csv)}</layer>"
  end

  def parse(body, tilesets: [sheet], width: 2, height: 2, attributes: '')
    tiled::Map.parse(%(<map orientation="orthogonal" width="#{width}" height="#{height}" tilewidth="16" ) +
                     %(tileheight="16" #{attributes}>#{tilesets.join}#{body}</map>))
  end

  def build(...) = described_class.from_tiled(parse(...))

  def cells(map, index)
    (0...map.height).flat_map { |row| (0...map.width).map { |col| map.tile(index, col, row) } }
  end

  def bool_property(name, value) = %(<properties><property name="#{name}" type="bool" value="#{value}"/></properties>)

  # The other side of the contract RGame::Core::TileMapRenderer draws against:
  # the shape it prescribes, written as Tiled would write it. Local tile 0 is
  # animated through locals 0 and 1, local 2 has a collision shape, gid 2
  # carries the flags Tiled sets for a quarter turn clockwise, and the canopy is
  # hidden at half opacity. Tile 4 is the only tile of a second tileset, which
  # has a drawing offset.
  def tile_map
    frames = '<frame tileid="0" duration="100"/><frame tileid="1" duration="100"/>'
    tiles = %(<tile id="0"><animation>#{frames}</animation></tile><tile id="2">#{solid_shape}</tile>)
    yield build(layer([1, 0xA0000002, 0, 3]) +
                layer([0, 0, 4, 0], name: 'canopy', attributes: 'visible="0" opacity="0.5"',
                                    properties: bool_property('above', true)),
                tilesets: [sheet(count: 3, tiles: tiles),
                           sheet(firstgid: 4, name: 'props', count: 1, tiles: '<tileoffset x="2" y="-4"/>')])
  end

  it_behaves_like 'a tile map'

  describe 'tile ids' do
    let(:map) { build(layer([1, 4, 10, 12]), tilesets: [sheet, sheet(firstgid: 10, name: 'water', count: 3)]) }

    it 'are dense and start at 1, whatever gaps the first gids leave' do
      expect(cells(map, 0)).to eq([1, 4, 5, 7])
    end

    it 'count every tile of every tileset' do
      expect(map.tile_count).to eq(7)
    end

    it 'leave 0 as the empty cell, with no tile behind it' do
      expect([map.tile_table.first, map.tile(0, -1, 0), map.solid?(0)]).to eq([nil, 0, false])
    end

    it "number a collection's tiles in the order of their ids" do
      collection = '<tileset firstgid="1" name="props" tilewidth="16" tileheight="16">' \
                   '<tile id="0"><image source="a.png"/></tile><tile id="7"><image source="b.png"/></tile>' \
                   '<tile id="3"><image source="c.png"/></tile></tileset>'
      map = build(layer([8, 4, 1, 0]), tilesets: [collection])

      expect(cells(map, 0)).to eq([3, 2, 1, 0])
    end

    it 'raise for a gid no tileset covers, naming the layer and the cell' do
      expect { build(layer([1, 0, 0, 9])) }
        .to raise_error(tiled::FormatError, /layer 'ground' at column 1, row 1 names gid 9/)
    end
  end

  describe 'the tile table' do
    let(:map) { build(layer([1, 4, 10, 12]), tilesets: [sheet, sheet(firstgid: 10, name: 'water', count: 3)]) }

    it 'resolves a gid from the second tileset to the second tileset' do
      # The first tileset holds four tiles, so gid 10 is local 0 of the second
      # and never local 9 of the first.
      expect(map.tile_table[5]).to eq(described_class::TileSource.new(tileset: 1, local_id: 0))
    end

    it 'keeps each tile of the first tileset in the first' do
      expect(map.tile_table[4]).to eq(described_class::TileSource.new(tileset: 0, local_id: 3))
    end
  end

  describe 'orientation' do
    # Tiled's flags and what each shows, as its own tile menu names them. The
    # diagonal flip happens first, then the horizontal and vertical.
    {
      0x00000000 => [0, false],
      0x80000000 => [0, true],  # flip horizontally
      0x40000000 => [2, true],  # flip vertically
      0xC0000000 => [2, false], # rotate 180°
      0x20000000 => [1, true],  # flip across the diagonal
      0xA0000000 => [1, false], # rotate 90° clockwise
      0x60000000 => [3, false], # rotate 90° counterclockwise
      0xE0000000 => [3, true]
    }.each do |flags, (turns, mirrored)|
      it "turns flags 0x#{flags.to_s(16)} into #{turns} quarter turns#{', mirrored' if mirrored}" do
        orientation = build(layer([1 | flags, 0, 0, 0])).orientation(0, 0, 0)

        expect([orientation.quarter_turns, orientation.mirrored?]).to eq([turns, mirrored])
      end
    end

    # spec/fixtures/orientations.tmx was painted in Tiled, one F in each of the
    # eight ways its stamp can turn one, between two empty cells. The table
    # above was written from Tiled's documentation; this is Tiled's own output.
    # Core's tile_map_renderer_spec.rb draws these eight values and checks the
    # pixels against what Tiled showed.
    it 'reads the eight turns Tiled painted into spec/fixtures/orientations.tmx' do
      map = described_class.from_tiled(tiled::Map.load('spec/fixtures/orientations.tmx'))
      read = (1..8).map { map.orientation(0, it, 0) }.map { [it.quarter_turns, it.mirrored?] }

      expect(read).to eq([[0, false], [0, true], [2, true], [2, false],
                          [3, false], [3, true], [1, true], [1, false]])
    end

    it 'answers one of the eight frozen values, never a new one' do
      orientation = build(layer([0xA0000001, 0, 0, 0])).orientation(0, 0, 0)

      expect(orientation).to be(described_class::Orientation::ALL[1]).and be_frozen
    end

    it 'keeps the flip bits out of the tile id' do
      expect(build(layer([0xE0000002, 0, 0, 0])).tile(0, 0, 0)).to eq(2)
    end

    it 'allocates no plane for a map with no turned tile, and answers the identity' do
      map = build(layer([1, 2, 3, 4]))

      expect(map.instance_variable_get(:@orientations)).to be_nil
      expect(map.orientation(0, 1, 1)).to be(described_class::Orientation::IDENTITY)
    end
  end

  describe 'layers' do
    let(:map) do
      hills = layer([2, 0, 0, 0], name: 'hills', attributes: 'opacity="0.5"')
      build(%(<group name="Background" opacity="0.5">#{layer([1, 0, 0, 0], name: 'sky')}) +
            %(<group name="Far" visible="0">#{hills}</group></group>) +
            %(<objectgroup name="spawns"/>#{layer([3, 0, 0, 0], name: 'ground')}))
    end

    it 'flatten depth first, with no index for a group' do
      expect((0...map.layer_count).map { map.layer(it).path }).to eq([%w[Background sky], %w[Background Far hills],
                                                                      ['spawns'], ['ground']])
    end

    it 'multiply opacity down the tree' do
      expect((0...map.layer_count).map { map.layer(it).opacity }).to eq([0.5, 0.25, 1.0, 1.0])
    end

    it 'hide a layer inside a hidden group' do
      expect((0...map.layer_count).map { map.layer(it).visible? }).to eq([true, false, true, true])
    end

    it 'keep every layer an index, the kinds with no tiles answering 0' do
      expect([map.layer(2).kind, map.tile(2, 0, 0), map.tile(3, 0, 0)]).to eq([:object, 0, 3])
    end

    it 'raise for a layer the map does not have' do
      expect { map.layer(4) }.to raise_error(IndexError)
    end
  end

  describe '#layer_index' do
    let(:map) do
      build(%(<group name="Near">#{layer([0] * 4, name: 'trees')}</group>) +
            %(<group name="Far">#{layer([0] * 4, name: 'trees')}#{layer([0] * 4, name: 'hills')}</group>))
    end

    it 'takes a name' do
      expect(map.layer_index('hills')).to eq(2)
    end

    it "takes a 'Group/child' path" do
      expect(map.layer_index('Far/trees')).to eq(1)
    end

    it 'raises naming the layers when nothing matches' do
      expect { map.layer_index('canopy') }
        .to raise_error(KeyError, "no layer 'canopy' in this map (has: Near/trees, Far/trees, Far/hills)")
    end

    it 'raises naming the matches when a name is in two groups' do
      expect { map.layer_index('trees') }.to raise_error(KeyError, %r{names 2 layers .* Near/trees, Far/trees})
    end
  end

  describe 'above?' do
    it 'reads the bool property once, into the layer' do
      map = build(layer([0] * 4) + layer([0] * 4, name: 'canopy', properties: bool_property('above', true)))

      expect([map.layer(0).above?, map.layer(1).above?]).to eq([false, true])
    end

    it 'raises for an above property that is not a bool, rather than reading it as false' do
      text = '<properties><property name="above" value="true"/></properties>'

      expect { build(layer([0] * 4, properties: text)) }.to raise_error(tiled::FormatError, /make it a bool/)
    end
  end

  describe 'solidity' do
    let(:map) do
      build(layer([1, 0, 0, 0]) + layer([0, 3, 0, 0], name: 'walls', attributes: 'visible="0"'),
            tilesets: [sheet(tiles: %(<tile id="2">#{solid_shape}</tile>))])
    end

    it 'is a tile with a collision shape' do
      expect([map.solid?(1), map.solid?(3)]).to eq([false, true])
    end

    it 'counts a hidden layer, since hiding a layer in Tiled does not open its walls' do
      expect(map.solid_tile?(1, 0)).to be(true)
    end

    it 'is not outside the map' do
      expect(map.solid_tile?(-1, 0)).to be(false)
    end

    it 'answers a world position through the tile under it' do
      expect([map.solid_at?(20.0, 3.0), map.solid_at?(3.0, 3.0)]).to eq([true, false])
    end
  end

  describe 'what a tile is' do
    let(:map) do
      tiles = '<tile id="1" type="Chest"><properties><property name="gold" type="int" value="5"/></properties></tile>'
      build(layer([1, 2, 0, 0]), tilesets: [sheet(tiles: tiles)])
    end

    it 'keeps the class the designer gave it, or nil' do
      expect([map.tile_class(1), map.tile_class(2)]).to eq([nil, 'Chest'])
    end

    it 'keeps its properties, EMPTY when it has none' do
      expect([map.tile_properties(1), map.tile_properties(2)['gold']]).to eq([RGame::Engine::Properties::EMPTY, 5])
    end
  end

  describe '#tile_offset' do
    let(:map) do
      build(layer([1, 5, 0, 0]),
            tilesets: [sheet, sheet(firstgid: 5, name: 'props', count: 2, tiles: '<tileoffset x="3" y="-6"/>')])
    end

    it "is its tileset's drawing offset" do
      expect([map.tile_offset(5), map.tile_offset(6)]).to eq([[3, -6], [3, -6]])
    end

    it 'is [0, 0] for a tile of a tileset with none, and for the empty cell' do
      expect([map.tile_offset(1), map.tile_offset(0)]).to eq([[0, 0], [0, 0]])
    end

    # A map with no offset anywhere holds one pair, not one per tile.
    it 'is the same frozen pair for every tile drawn at no offset' do
      expect(map.tile_offset(1)).to be_frozen.and(equal(map.tile_offset(4)))
    end
  end

  describe '#frame_tile' do
    let(:frames) { [[0, 100], [1, 250], [2, 50]] }
    let(:map) do
      animation = frames.map { |id, ms| %(<frame tileid="#{id}" duration="#{ms}"/>) }.join
      build(layer([1, 0, 0, 0]), tilesets: [sheet(tiles: %(<tile id="0"><animation>#{animation}</animation></tile>))])
    end

    # Tileset#frame_local_id, which this replaced: whole milliseconds,
    # truncated from the seconds the game counts in.
    def milliseconds_frame(elapsed)
      into = (elapsed * 1000).to_i % frames.sum(&:last)
      frames.each do |id, ms|
        return id + 1 if into < ms

        into -= ms
      end
    end

    it 'takes seconds, and loops' do
      expect([0.0, 0.15, 0.36, 0.45].map { map.frame_tile(1, it) }).to eq([1, 2, 3, 1])
    end

    it 'shows the frame the millisecond arithmetic showed, on every tick of a minute at 60 Hz' do
      elapsed = 0.0
      shown = Array.new(3600) { elapsed += 1 / 60.0 }.map { [map.frame_tile(1, it), milliseconds_frame(it)] }

      expect(shown.reject { |new, old| new == old }).to be_empty
    end

    it 'leaves a tile that does not animate alone' do
      expect(map.frame_tile(2, 0.15)).to eq(2)
    end

    it 'lists the tiles that animate' do
      expect(map.animated_tiles).to eq([1])
    end
  end

  describe 'objects' do
    def objects(body, **) = build(%(<objectgroup name="things">#{body}</objectgroup>), **).objects

    it "moves a tile object's corner from its bottom-left to its top-left" do
      object = objects('<object id="1" gid="2" x="100" y="200" width="16" height="16"/>').first

      expect([object.x, object.y, object.tile]).to eq([100.0, 184.0, 2])
    end

    it 'turns the top-left about the bottom-left corner the file rotates a tile object about' do
      # Turned 90° clockwise about its bottom-left corner, the tile lies to the
      # right of that corner, so the corner that was on top is now 16 px right
      # of it. Moving (x, y) up first and rotating after would put it 16 px
      # left, with the tile hanging over the wrong side.
      object = objects('<object id="1" gid="2" x="100" y="200" width="16" height="16" rotation="90"/>').first

      expect([object.x, object.y.round(9), object.rotation]).to eq([116.0, 200.0, 90.0])
    end

    it 'leaves a rectangle where the file puts it' do
      object = objects('<object id="1" x="10" y="20" width="30" height="40"/>').first

      expect([object.x, object.y, object.tile, object.shape]).to eq([10.0, 20.0, nil, :rectangle])
    end

    it 'makes polygon points absolute' do
      object = objects('<object id="1" x="10" y="20"><polygon points="0,0 16,0 16,8"/></object>').first

      expect(object.points).to eq([[10.0, 20.0], [26.0, 20.0], [26.0, 28.0]])
    end

    it "folds a tile object's flip bits into its orientation" do
      object = objects(%(<object id="1" gid="2147483650" x="0" y="16" width="16" height="16"/>)).first

      expect([object.tile, object.orientation.mirrored?]).to eq([2, true])
    end

    it 'names the layer the object sits in' do
      map = build(%(#{layer([0] * 4)}<objectgroup name="things"><object id="1" x="0" y="0"/></objectgroup>))

      expect(map.objects.first.layer).to eq(1)
    end
  end

  describe 'a fixed map and its infinite twin' do
    # The same picture twice: a tile in the top-left and a flipped one in the
    # bottom-right cell, a tile object and a polygon. The infinite one is
    # painted around Tiled's origin, so its box starts at cell (-2, -2).
    let(:body) do
      lambda do |data, shift|
        <<~TMX
          <layer name="ground" width="4" height="4">#{data}</layer>
          <objectgroup name="things">
            <object id="1" gid="2" x="#{16 + shift}" y="#{48 + shift}" width="16" height="16"/>
            <object id="2" x="#{8 + shift}" y="#{8 + shift}"><polygon points="0,0 16,0 16,16"/></object>
          </objectgroup>
          <imagelayer name="sky" offsetx="#{10 + shift}" offsety="#{shift}"><image source="sky.png"/></imagelayer>
        TMX
      end
    end
    let(:fixed) do
      build(body.call(TiledFixture.data([1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x80000003], encoding: :csv), 0),
            width: 4, height: 4)
    end
    let(:infinite) do
      data = TiledFixture.chunked_data({ [-2, -2] => [1, 0, 0, 0], [0, 0] => [0, 0, 0, 0x80000003] })
      build(body.call(data, -32), width: 30, height: 30, attributes: 'infinite="1"')
    end

    it 'has the same size' do
      expect([infinite.width, infinite.height]).to eq([fixed.width, fixed.height])
    end

    it 'holds the same tiles, turned the same way' do
      expect(cells(infinite, 0)).to eq(cells(fixed, 0))
      expect(infinite.orientation(0, 3, 3)).to be(fixed.orientation(0, 3, 3))
    end

    it 'puts every object in the same place' do
      expect(infinite.objects).to eq(fixed.objects)
    end

    it 'puts an image layer at the same offset' do
      expect(infinite.image_layers.map { [it.offset_x, it.offset_y] }).to eq([[10.0, 0.0]])
      expect(fixed.image_layers.map { [it.offset_x, it.offset_y] }).to eq([[10.0, 0.0]])
    end
  end

  describe 'a built map' do
    let(:map) do
      tiles = layer([1, 0x80000002, 0, 0], properties: bool_property('above', false))
      build(%(#{tiles}<objectgroup name="o"><object id="1" gid="1" x="0" y="16"/></objectgroup>),
            tilesets: [sheet(tiles: %(<tile id="0" type="Rock">#{solid_shape}</tile>))])
    end

    # Everything a built map can reach, following instance variables, Arrays,
    # Hashes and Data members down to the leaves.
    def reachable(value, seen = {}.compare_by_identity)
      return seen if seen.key?(value)

      seen[value] = true
      children = case value
                 when Array then value
                 when Hash then value.to_a.flatten(1)
                 when Data then value.to_h.values
                 else value.instance_variables.map { value.instance_variable_get(it) }
                 end
      children.each { reachable(it, seen) }
      seen
    end

    it 'reaches no parse type' do
      leaked = reachable(map).keys.map(&:class).uniq.select { it.name.to_s.start_with?('RGame::Engine::Tiled') }

      expect(leaked).to be_empty
    end

    it 'records the parse it came from' do
      expect(map.source.parser_version).to eq(tiled::PARSER_VERSION)
    end

    it 'is built from plain Arrays, not a Tensor' do
      by_hand = described_class.new(
        width: 2, height: 1, tile_width: 16, tile_height: 16,
        layers: [described_class::Layer.new(index: 0, path: ['ground'], kind: :tile, class_name: '',
                                            visible: true, opacity: 1.0, above: false,
                                            properties: RGame::Engine::Properties::EMPTY)],
        cells: [[1, 2]], tile_table: [nil, described_class::TileSource.new(tileset: 0, local_id: 0),
                                      described_class::TileSource.new(tileset: 0, local_id: 1)],
        solid: [false, false, true], tile_classes: [nil, nil, nil],
        tile_properties: Array.new(3, RGame::Engine::Properties::EMPTY), frames: [nil, nil, nil]
      )

      expect([by_hand.tile(0, 1, 0), by_hand.solid_at?(20.0, 3.0)]).to eq([2, true])
    end
  end

  describe 'examples/assets/town.tmx' do
    let(:path) { File.expand_path('../../../examples/assets/town.tmx', __dir__) }
    let(:map) { described_class.from_tiled(tiled::Map.load(path)) }

    it 'is solid exactly where the parser before the transform said it was' do
      # Written by that parser, the last time it ran: one line per row, # for a
      # solid cell. The collision the examples play on is this picture.
      expected = File.read(File.expand_path('../../fixtures/town_solidity.txt', __dir__)).lines(chomp: true)
      solidity = (0...map.height).map { |row| (0...map.width).map { map.solid_tile?(it, row) ? '#' : '.' }.join }

      expect(solidity).to eq(expected)
    end

    it 'records the file it was read from' do
      expect(map.source.path).to eq(path)
    end
  end
end
