# frozen_string_literal: true

RSpec.describe RGame::Engine::Tiled::Tileset do
  def parse(body = '', attributes: 'tilewidth="16" tileheight="16"', source_path: nil)
    described_class.parse("<tileset #{attributes}>#{body}</tileset>", source_path: source_path)
  end

  let(:sheet) { '<image source="tiles.png" width="192" height="176"/>' }

  describe 'a sheet' do
    it 'defaults spacing and margin to 0' do
      tileset = parse(sheet, attributes: 'tilewidth="16" tileheight="16" tilecount="132" columns="12"')

      expect([tileset.spacing, tileset.margin]).to eq([0, 0])
    end

    it 'reads margin and spacing' do
      tileset = parse(sheet, attributes: 'tilewidth="16" tileheight="16" margin="1" spacing="2"')

      expect([tileset.margin, tileset.spacing]).to eq([1, 2])
    end

    it 'takes columns and tile_count as the file states them' do
      tileset = parse(sheet, attributes: 'tilewidth="16" tileheight="16" tilecount="100" columns="10"')

      expect([tileset.columns, tileset.tile_count]).to eq([10, 100])
    end

    it 'counts columns and tiles from the image when the file leaves them out, margin and spacing included' do
      # (1 + 4 * 16 + 3 * 2 + 1) = 72 wide, (1 + 3 * 16 + 2 * 2 + 1) = 54 high
      image = '<image source="tiles.png" width="72" height="54"/>'
      tileset = parse(image, attributes: 'tilewidth="16" tileheight="16" margin="1" spacing="2"')

      expect([tileset.columns, tileset.tile_count]).to eq([4, 12])
    end

    it 'raises when it has to count columns and the image states no width' do
      expect { parse('<image source="tiles.png"/>', attributes: 'name="t" tilewidth="16" tileheight="16"') }
        .to raise_error(RGame::Engine::Tiled::FormatError, /'t'.*no columns/)
    end

    it 'reads its image, size included' do
      expect(parse(sheet).image).to eq(described_class::Image.new(source: 'tiles.png', width: 192, height: 176))
    end

    it 'is not a collection' do
      expect(parse(sheet)).not_to be_collection
    end

    it 'reads name, class and properties' do
      tileset = parse("#{sheet}<properties><property name=\"biome\" value=\"forest\"/></properties>",
                      attributes: 'name="town" class="Terrain" tilewidth="16" tileheight="16"')

      expect([tileset.name, tileset.class_name, tileset.properties['biome']]).to eq(%w[town Terrain forest])
    end
  end

  describe 'a collection of images' do
    subject(:tileset) do
      attributes = 'tilewidth="32" tileheight="48" tilecount="2" columns="0"'
      parse(<<~XML, attributes: attributes, source_path: 'art/props.tsx')
        <tile id="0"><image source="barrel.png" width="32" height="32"/></tile>
        <tile id="3"><image source="../trees/oak.png" width="32" height="48"/></tile>
      XML
    end

    it 'is a collection' do
      expect(tileset).to be_collection
    end

    it 'gives each tile its own image, resolved relative to the tileset' do
      expect(tileset.tile(3).image)
        .to eq(described_class::Image.new(source: 'art/../trees/oak.png', width: 32, height: 48))
    end

    it 'counts the tiles it holds when the file leaves the count out' do
      tileset = parse('<tile id="0"><image source="a.png"/></tile><tile id="5"><image source="b.png"/></tile>')

      expect([tileset.columns, tileset.tile_count]).to eq([0, 2])
    end
  end

  describe 'the drawing offset' do
    it 'reads <tileoffset>' do
      tileset = parse("#{sheet}<tileoffset x=\"4\" y=\"-8\"/>")

      expect([tileset.offset_x, tileset.offset_y]).to eq([4, -8])
    end

    it 'defaults to 0 without one' do
      expect([parse(sheet).offset_x, parse(sheet).offset_y]).to eq([0, 0])
    end
  end

  describe 'a tile' do
    it 'is nil where the file says nothing about it' do
      expect(parse(sheet).tile(7)).to be_nil
    end

    it "reads its class from Tiled 1.9's class attribute" do
      expect(parse(%(#{sheet}<tile id="2" class="Water"/>)).tile(2).class_name).to eq('Water')
    end

    it "reads its class from later versions' type attribute" do
      expect(parse(%(#{sheet}<tile id="2" type="Water"/>)).tile(2).class_name).to eq('Water')
    end

    it 'has an empty class and EMPTY properties when it states neither' do
      tile = parse(%(#{sheet}<tile id="2"/>)).tile(2)

      expect([tile.class_name, tile.properties]).to eq(['', RGame::Engine::Properties::EMPTY])
    end

    it 'reads its properties, with file properties resolved against the tileset' do
      tileset = parse(%(#{sheet}<tile id="2"><properties><property name="sound" type="file" value="splash.ogg"/>
                      </properties></tile>), source_path: 'art/tiles.tsx')

      expect(tileset.tile(2).properties['sound']).to eq('art/splash.ogg')
    end
  end

  describe 'an animation' do
    subject(:tile) do
      parse(%(#{sheet}<tile id="4"><animation><frame tileid="4" duration="100"/>
              <frame tileid="5" duration="250"/></animation></tile>)).tile(4)
    end

    it 'keeps each duration in milliseconds, as the file states it' do
      expect(tile.frames).to eq([RGame::Engine::Tiled::Frame.new(tile_id: 4, duration_ms: 100),
                                 RGame::Engine::Tiled::Frame.new(tile_id: 5, duration_ms: 250)])
    end

    it 'makes the tile animated' do
      expect(tile).to be_animated
    end

    it 'leaves a tile without one unanimated, with no frames' do
      tile = parse(%(#{sheet}<tile id="2"/>)).tile(2)

      expect([tile.animated?, tile.frames]).to eq([false, []])
    end
  end

  describe 'collision shapes' do
    subject(:shapes) do
      parse(<<~XML).tile(7).collision_shapes
        #{sheet}
        <tile id="7">
          <objectgroup draworder="index">
            <object id="1" type="Water" x="0" y="8" width="16" height="8">
              <properties><property name="depth" type="int" value="2"/></properties>
            </object>
            <object id="2" class="Ledge" x="2" y="0"><polygon points="0,0 12,0 6,4.5"/></object>
            <object id="3" x="8" y="8" width="4" height="4"><ellipse/></object>
          </objectgroup>
        </tile>
      XML
    end

    it 'keeps each shape with its class and properties' do
      expect([shapes[0].class_name, shapes[0].properties['depth'], shapes[1].class_name]).to eq(['Water', 2, 'Ledge'])
    end

    it 'keeps the geometry as the file states it' do
      expect([shapes[0].x, shapes[0].y, shapes[0].width, shapes[0].height]).to eq([0.0, 8.0, 16.0, 8.0])
    end

    it 'reads each shape kind' do
      expect(shapes.map(&:shape)).to eq(%i[rectangle polygon ellipse])
    end

    it 'keeps polygon points relative to the object, as pairs' do
      expect(shapes[1].points).to eq([[0.0, 0.0], [12.0, 0.0], [6.0, 4.5]])
    end

    it 'is empty for a tile with no objectgroup' do
      expect(parse(%(#{sheet}<tile id="2"/>)).tile(2).collision_shapes).to be_empty
    end
  end

  describe 'loading a .tsx' do
    it 'resolves the sheet image relative to the .tsx, from a subdirectory' do
      path = TiledFixture.write_tileset('<image source="../png/tiles.png" width="64" height="64"/>',
                                        subdirectory: 'tsx')

      expect(described_class.load(path).image.source).to eq(File.join(File.dirname(path), '../png/tiles.png'))
    end

    it 'keeps an absolute image path' do
      absolute = File.expand_path('/srv/tiles.png')
      path = TiledFixture.write_tileset(%(<image source="#{absolute}" width="64" height="64"/>))

      expect(described_class.load(path).image.source).to eq(absolute)
    end
  end

  describe 'a file rgame cannot read' do
    it 'raises when the root is not a tileset, naming the file' do
      expect { described_class.parse('<map/>', source_path: 'level.tsx') }
        .to raise_error(RGame::Engine::Tiled::FormatError, /level\.tsx.*<tileset>/)
    end

    it 'raises on XML that is not well-formed' do
      expect { described_class.parse('<tileset', source_path: 'level.tsx') }
        .to raise_error(RGame::Engine::Tiled::FormatError, /level\.tsx.*well-formed/)
    end

    it 'raises without a tile size' do
      expect { parse(sheet, attributes: 'tilewidth="16"') }
        .to raise_error(RGame::Engine::Tiled::FormatError, /no tileheight/)
    end

    it 'raises on a size that is not a number, naming the attribute and the file' do
      expect { parse(sheet, attributes: 'tilewidth="wide" tileheight="16"', source_path: 'level.tsx') }
        .to raise_error(RGame::Engine::Tiled::FormatError, /level\.tsx.*tilewidth="wide"/)
    end

    it 'raises on an image embedded as data' do
      expect { parse('<image format="png"><data encoding="base64">AAAA</data></image>') }
        .to raise_error(RGame::Engine::Tiled::FormatError, /embeds its image data/)
    end

    it 'raises on an animation frame with no duration' do
      expect { parse(%(#{sheet}<tile id="4"><animation><frame tileid="4"/></animation></tile>)) }
        .to raise_error(RGame::Engine::Tiled::FormatError, /<frame>.*no duration/)
    end
  end

  it 'is frozen, and so are its tiles' do
    tileset = parse(%(#{sheet}<tile id="2"/>))

    expect([tileset, tileset.tiles, tileset.tile(2)]).to all(be_frozen)
  end
end
