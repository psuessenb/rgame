# frozen_string_literal: true

RSpec.describe RGame::Engine::Tiled::Map do
  def parse(body = '', attributes: 'width="3" height="2" tilewidth="16" tileheight="16"', source_path: nil)
    described_class.parse(%(<map orientation="orthogonal" #{attributes}>#{body}</map>), source_path: source_path)
  end

  def tile_layer(gids, width: 3, height: 2, attributes: '', **encoding)
    %(<layer id="1" name="ground" width="#{width}" height="#{height}" #{attributes}>) +
      "#{TiledFixture.data(gids, **encoding)}</layer>"
  end

  def load(files) = described_class.load(File.join(TiledFixture.write_files(files), 'map.tmx'))

  def tmx(body, attributes: 'width="3" height="2" tilewidth="16" tileheight="16"')
    %(<?xml version="1.0" encoding="UTF-8"?>\n<map orientation="orthogonal" #{attributes}>#{body}</map>)
  end

  def tsx(body = '<image source="tiles.png" width="64" height="64"/>', name: 'tiles')
    %(<tileset name="#{name}" tilewidth="16" tileheight="16">#{body}</tileset>)
  end

  let(:grid) { [1, 0, 3, 0x80000002, 5, 6] }

  describe 'every encoding' do
    [[:xml, nil], [:csv, nil], [:base64, nil], %i[base64 gzip], %i[base64 zlib]].each do |encoding, compression|
      it "decodes #{[encoding, compression].compact.join(' with ')} to the same gids" do
        layer = parse(tile_layer(grid, encoding: encoding, compression: compression)).layers.first

        expect(layer.gids).to eq(grid)
      end
    end

    it 'reads a missing gid in XML as 0' do
      layer = parse('<layer width="2" height="1"><data><tile/><tile gid="4"/></data></layer>',
                    attributes: 'width="2" height="1" tilewidth="16" tileheight="16"').layers.first

      expect(layer.gids).to eq([0, 4])
    end

    it 'raises on a layer holding fewer tiles than its size, naming the file' do
      expect { parse(tile_layer([1, 2, 3], encoding: :csv), source_path: 'level.tmx') }
        .to raise_error(RGame::Engine::Tiled::FormatError, /<data> in level\.tmx holds 3 tiles where .* 6/)
    end

    it 'raises on CSV that is not numbers' do
      expect { parse('<layer width="3" height="2"><data encoding="csv">1,a</data></layer>') }
        .to raise_error(RGame::Engine::Tiled::FormatError, /CSV/)
    end

    it 'raises on data that does not decompress' do
      bad = '<layer width="3" height="2"><data encoding="base64" compression="zlib">AAAA</data></layer>'

      expect { parse(bad) }.to raise_error(RGame::Engine::Tiled::FormatError, /does not decompress as zlib/)
    end

    it 'raises on an encoding Tiled does not write' do
      expect { parse('<layer width="3" height="2"><data encoding="hex">00</data></layer>') }
        .to raise_error(RGame::Engine::Tiled::FormatError, /encoding="hex"/)
    end
  end

  describe 'zstd' do
    it 'raises, naming the compression and saying rgame does not carry it' do
      expect { parse(tile_layer(grid, compression: :zstd), source_path: 'level.tmx') }
        .to raise_error(RGame::Engine::Tiled::FormatError,
                        /level\.tmx.*compression="zstd".*gem rgame does not carry.*zlib or gzip/)
    end
  end

  describe 'orientation' do
    %w[isometric staggered hexagonal].each do |orientation|
      it "raises on #{orientation}, naming it and the file" do
        expect { described_class.parse(%(<map orientation="#{orientation}"/>), source_path: 'level.tmx') }
          .to raise_error(RGame::Engine::Tiled::FormatError, /<map> in level\.tmx.*"#{orientation}".*orthogonal/)
      end
    end

    it 'reads a map that states none as orthogonal' do
      expect(described_class.parse('<map width="1" height="1" tilewidth="8" tileheight="8"/>').orientation)
        .to eq(:orthogonal)
    end
  end

  describe 'several tilesets' do
    subject(:tilesets) do
      load('map.tmx' => tmx(<<~XML), 'sets/outside.tsx' => tsx(name: 'outside'), 'sets/tiles.png' => '')
        <tileset firstgid="65" source="sets/outside.tsx"/>
        <tileset firstgid="1" name="inside" tilewidth="16" tileheight="16" tilecount="64" columns="8">
          <image source="inside.png" width="128" height="128"/>
        </tileset>
      XML
    end

    it 'reads all of them, in firstgid order, external and embedded alike' do
      expect(tilesets.tilesets.map { [it.firstgid, it.tileset.name] }).to eq([[1, 'inside'], [65, 'outside']])
    end

    it "resolves an embedded tileset's image against the map" do
      expect(File.basename(File.dirname(tilesets.tilesets.first.tileset.image.source))).to start_with('set_')
    end

    it "resolves an external tileset's image against the .tsx" do
      expect(tilesets.tilesets.last.tileset.image.source).to end_with(File.join('sets', 'tiles.png'))
    end

    it 'raises when a .tsx the map names is not there, naming both' do
      expect { load('map.tmx' => tmx('<tileset firstgid="1" source="missing.tsx"/>')) }
        .to raise_error(RGame::Engine::Tiled::FormatError, /map\.tmx names the tileset missing\.tsx, and .* not there/)
    end

    it 'raises on an external tileset in a map parsed from a string' do
      expect { parse('<tileset firstgid="1" source="tiles.tsx"/>') }
        .to raise_error(RGame::Engine::Tiled::FormatError, /tiles\.tsx.*load the map from its file/)
    end
  end

  describe 'the gid mask' do
    it 'keeps the three flip bits' do
      gids = [0x80000001, 0x40000001, 0x20000001, 0xE0000001, 1, 0]

      expect(parse(tile_layer(gids)).layers.first.gids).to eq(gids)
    end

    it 'clears bit 29 on an orthogonal map' do
      expect(parse(tile_layer([0x10000001, 0x90000002, 0, 0, 0, 0])).layers.first.gids.first(2))
        .to eq([1, 0x80000002])
    end

    it 'is 0x0FFFFFFF' do
      expect(RGame::Engine::Tiled::GID_MASK & 0xF0000002).to eq(2)
    end

    it 'clears bit 29 on a tile object too' do
      object = parse('<objectgroup><object id="1" gid="268435459"/></objectgroup>').layers.first.objects.first

      expect(object.gid).to eq(3)
    end
  end

  describe 'chunks' do
    subject(:map) do
      parse(<<~XML, attributes: 'width="30" height="20" tilewidth="16" tileheight="16" infinite="1"')
        <layer id="1" name="ground" width="30" height="20">
          #{TiledFixture.chunked_data({ [-2, 0] => [1, 0, 0, 2], [0, 0] => [0, 0, 0, 0] })}
        </layer>
        <layer id="2" name="roof" width="30" height="20">
          #{TiledFixture.chunked_data({ [2, 2] => [0, 0, 0, 7] }, encoding: :base64, compression: :zlib)}
        </layer>
      XML
    end

    it 'is infinite' do
      expect(map).to be_infinite
    end

    it 'takes the box around the non-empty chunks of every layer at once' do
      expect([map.width, map.height]).to eq([6, 4])
    end

    it 'records the Tiled cell the box starts on' do
      expect([map.origin_col, map.origin_row]).to eq([-2, 0])
    end

    it 'gives every tile layer the same box' do
      expect(map.layers.map { [it.width, it.height] }).to eq([[6, 4], [6, 4]])
    end

    it 'places each tile at its cell less the origin' do
      ground, roof = map.layers

      expect([ground.gid(0, 0), ground.gid(1, 1), roof.gid(5, 3)]).to eq([1, 2, 7])
    end

    it 'leaves the rest of the box empty' do
      expect(map.layers.sum { it.gids.count(&:nonzero?) }).to eq(3)
    end

    it 'reads an infinite map with no tiles as 0 by 0' do
      empty = parse('<layer width="30" height="20"><data encoding="csv"/></layer>',
                    attributes: 'width="30" height="20" tilewidth="16" tileheight="16" infinite="1"')

      expect([empty.width, empty.height, empty.layers.first.gids]).to eq([0, 0, []])
    end

    it 'gives a fixed map an origin of 0, 0' do
      map = parse(tile_layer(grid))

      expect([map.infinite?, map.origin_col, map.origin_row]).to eq([false, 0, 0])
    end
  end

  describe 'groups' do
    subject(:map) do
      parse(<<~XML)
        <group id="1" name="outer" opacity="0.5">
          <group id="2" name="inner" opacity="0.5" visible="0">
            #{tile_layer(grid, attributes: 'opacity="0.8"').sub('id="1"', 'id="3"')}
          </group>
          <objectgroup id="4" name="things"/>
        </group>
      XML
    end

    let(:inner) { map.layers.first.layers.first }
    let(:leaf) { inner.layers.first }

    it 'nest' do
      expect([map.layers.first.name, inner.name, leaf.name]).to eq(%w[outer inner ground])
    end

    it 'multiply opacity down the tree' do
      expect(leaf.effective_opacity).to be_within(1e-9).of(0.2)
    end

    it "keep each layer's own opacity as the file states it" do
      expect(leaf.opacity).to eq(0.8)
    end

    it 'hide everything under a hidden group' do
      expect([leaf.visible?, leaf.effective_visible?]).to eq([true, false])
    end

    it 'leave a sibling of the hidden group visible' do
      expect(map.layers.first.layers.last).to be_effective_visible
    end
  end

  describe 'the layer tree' do
    subject(:layers) do
      parse(<<~XML).layers
        <objectgroup id="1" name="a"/>
        #{tile_layer(grid).sub('id="1" name="ground"', 'id="2" name="b"')}
        <group id="3" name="c"><imagelayer id="4" name="d"/></group>
        <imagelayer id="5" name="e"/>
      XML
    end

    it "keeps Tiled's order, bottom first" do
      expect(layers.map(&:name)).to eq(%w[a b c e])
    end

    it 'keeps the kind of each layer' do
      expect(layers.map(&:class).map { it.name.split('::').last })
        .to eq(%w[ObjectLayer TileLayer GroupLayer ImageLayer])
    end

    it 'keeps a group as a node rather than flattening it' do
      expect(layers[2].layers.map(&:name)).to eq(['d'])
    end

    it 'reads id, name, class and properties on a layer' do
      layer = parse('<imagelayer id="9" name="sky" class="Backdrop"><properties>' \
                    '<property name="above" type="bool" value="true"/></properties></imagelayer>').layers.first

      expect([layer.id, layer.name, layer.class_name, layer.properties['above']]).to eq([9, 'sky', 'Backdrop', true])
    end

    it 'is frozen' do
      expect([layers, layers[1], layers[1].gids, layers[2].layers]).to all(be_frozen)
    end
  end

  describe 'an image layer' do
    subject(:layer) do
      parse(<<~XML, source_path: 'maps/level.tmx').layers.first
        <imagelayer id="1" name="sky" offsetx="4" offsety="-2.5" repeatx="1">
          <image source="../art/sky.png" width="320" height="180"/>
        </imagelayer>
      XML
    end

    it 'reads its image, resolved against the map' do
      expect(layer.image)
        .to eq(RGame::Engine::Tiled::Tileset::Image.new(source: 'maps/../art/sky.png', width: 320, height: 180))
    end

    it 'reads its offset in pixels' do
      expect([layer.offset_x, layer.offset_y]).to eq([4.0, -2.5])
    end

    it 'reads repeat per axis' do
      expect([layer.repeat_x?, layer.repeat_y?]).to eq([true, false])
    end

    it 'has no image when it names none' do
      expect(parse('<imagelayer id="1"/>').layers.first.image).to be_nil
    end
  end

  describe 'a template' do
    subject(:objects) do
      load('map.tmx' => tmx(<<~XML),
        <tileset firstgid="1" source="tiles/props.tsx"/>
        <tileset firstgid="40" source="tiles/items.tsx"/>
        <objectgroup id="1">
          <object id="1" template="templates/chest.tx" x="32" y="48"/>
          <object id="2" template="templates/chest.tx" name="big" x="64" y="48" width="32">
            <properties><property name="contents" value="gold"/></properties>
          </object>
          <object id="3" template="templates/zone.tx" x="0" y="0"><ellipse/></object>
          <object id="4" template="templates/zone.tx" x="0" y="0"><capsule/></object>
        </objectgroup>
      XML
           'tiles/props.tsx' => tsx(name: 'props'), 'tiles/items.tsx' => tsx(name: 'items'),
           'templates/chest.tx' => <<~TX,
             <template>
               <tileset firstgid="1" source="../tiles/items.tsx"/>
               <object name="chest" type="Chest" gid="2147483651" width="16" height="16">
                 <properties>
                   <property name="contents" value="key"/>
                   <property name="open_sound" type="file" value="../sounds/creak.ogg"/>
                 </properties>
               </object>
             </template>
           TX
           'templates/zone.tx' => <<~TX).layers.first.objects
             <template><object type="Zone" width="8" height="8"><polygon points="0,0 8,0 4,8"/></object></template>
           TX
    end

    it 'fills what the object leaves out from the .tx' do
      expect([objects[0].name, objects[0].class_name, objects[0].width]).to eq(['chest', 'Chest', 16.0])
    end

    it "keeps the object's own attributes over the template's" do
      expect([objects[1].id, objects[1].name, objects[1].x, objects[1].width]).to eq([2, 'big', 64.0, 32.0])
    end

    it "merges properties by name, the object's winning" do
      expect([objects[0].properties['contents'], objects[1].properties['contents']]).to eq(%w[key gold])
    end

    it 'resolves a file property against the .tx that states it' do
      expect(objects[1].properties['open_sound']).to end_with(File.join('templates', '..', 'sounds', 'creak.ogg'))
    end

    it "moves a tile template's gid to where its tileset sits in the map, flip bits and all" do
      expect(objects[0].gid).to eq(0x80000000 | 42)
    end

    it "keeps the object's own shape over the template's" do
      expect([objects[2].shape, objects[2].class_name]).to eq([:ellipse, 'Zone'])
    end

    it "keeps the object's own capsule over the template's shape" do
      expect([objects[3].shape, objects[3].points]).to eq([:capsule, []])
    end

    it 'raises when the map does not name the tileset the template draws from' do
      files = { 'map.tmx' => tmx('<objectgroup><object id="1" template="t.tx"/></objectgroup>'),
                'items.tsx' => tsx,
                't.tx' => '<template><tileset firstgid="1" source="items.tsx"/><object gid="1"/></template>' }

      expect { load(files) }.to raise_error(RGame::Engine::Tiled::FormatError, /t\.tx draws a tile from .*items\.tsx/)
    end

    it 'raises when the .tx is not there' do
      expect { load('map.tmx' => tmx('<objectgroup><object id="1" template="gone.tx"/></objectgroup>')) }
        .to raise_error(RGame::Engine::Tiled::FormatError, /template gone\.tx/)
    end
  end

  describe 'paths' do
    it 'resolve the .tsx to the .tmx and its image to the .tsx, from different directories' do
      directory = TiledFixture.write_files(
        'maps/map.tmx' => tmx('<tileset firstgid="1" source="../shared/tiles.tsx"/>'),
        'shared/tiles.tsx' => tsx('<image source="png/tiles.png" width="64" height="64"/>')
      )
      map = described_class.load(File.join(directory, 'maps', 'map.tmx'))

      expect(map.tilesets.first.tileset.image.source).to end_with(File.join('..', 'shared', 'png', 'tiles.png'))
    end
  end

  describe 'an object layer' do
    subject(:layer) do
      parse(<<~XML).layers.first
        <objectgroup id="1" name="things" class="Spawns" draworder="index">
          <object id="1" name="chest" type="Chest" gid="5" x="32" y="48" width="16" height="16"/>
          <object id="2" x="8" y="8"><point/></object>
        </objectgroup>
      XML
    end

    it 'reads its draw order and class' do
      expect([layer.draw_order, layer.class_name]).to eq([:index, 'Spawns'])
    end

    it 'defaults the draw order to topdown' do
      expect(parse('<objectgroup id="1"/>').layers.first.draw_order).to eq(:topdown)
    end

    it 'raises on a draw order that is neither topdown nor index' do
      expect { parse('<objectgroup id="1" draworder="random"/>') }
        .to raise_error(RGame::Engine::Tiled::FormatError, /draworder="random", which is neither topdown nor index/)
    end

    it 'keeps a tile object at the bottom-left origin the file states' do
      expect([layer.objects[0].gid, layer.objects[0].x, layer.objects[0].y]).to eq([5, 32.0, 48.0])
    end

    it 'reads every object with its shape' do
      expect(layer.objects.map(&:shape)).to eq(%i[rectangle point])
    end
  end

  describe 'the map itself' do
    subject(:map) do
      parse('<properties><property name="music" value="town"/></properties>',
            attributes: 'width="3" height="2" tilewidth="16" tileheight="8" renderorder="left-up" ' \
                        'backgroundcolor="#80ff0000" class="Level"')
    end

    it 'reads its size and tile size' do
      expect([map.width, map.height, map.tile_width, map.tile_height]).to eq([3, 2, 16, 8])
    end

    it 'reads its render order as a symbol' do
      expect(map.render_order).to eq(:left_up)
    end

    it 'defaults the render order to right-down' do
      expect(parse.render_order).to eq(:right_down)
    end

    it 'reads its background colour' do
      expect(map.background_color).to eq(RGame::Util::Color.new(255, 0, 0, 128))
    end

    it 'has no background colour when it states none' do
      expect(parse.background_color).to be_nil
    end

    it 'reads its class and properties' do
      expect([map.class_name, map.properties['music']]).to eq(%w[Level town])
    end

    it 'raises when the root is not a map, naming the file' do
      expect { described_class.parse('<tileset/>', source_path: 'level.tmx') }
        .to raise_error(RGame::Engine::Tiled::FormatError, /level\.tmx is not a Tiled map/)
    end

    it 'raises without a size' do
      expect { described_class.parse('<map tilewidth="16" tileheight="16"/>') }
        .to raise_error(RGame::Engine::Tiled::FormatError, /<map> has no width/)
    end
  end
end
