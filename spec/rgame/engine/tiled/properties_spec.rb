# frozen_string_literal: true

require 'rexml/document'

RSpec.describe RGame::Engine::Tiled::Properties do
  def parse(body, source_path: nil)
    element = REXML::Document.new("<properties>#{body}</properties>").root
    described_class.parse(element, source_path: source_path)
  end

  def value(body, **) = parse(body, **)['p']

  describe 'a missing <properties> element' do
    it 'parses to EMPTY rather than nil' do
      expect(described_class.parse(nil)).to be(RGame::Engine::Properties::EMPTY)
    end

    it 'is empty and frozen' do
      expect(RGame::Engine::Properties::EMPTY).to be_empty.and be_frozen
    end
  end

  describe 'casting by type' do
    it 'reads a property with no type as a string' do
      expect(value('<property name="p" value="42"/>')).to eq('42')
    end

    it 'reads a string' do
      expect(value('<property name="p" type="string" value="hello"/>')).to eq('hello')
    end

    it 'reads a multi-line string from the element text' do
      expect(value("<property name=\"p\">first\nsecond</property>")).to eq("first\nsecond")
    end

    it 'reads an int, negative included' do
      expect(value('<property name="p" type="int" value="-7"/>')).to eq(-7)
    end

    it 'reads a float' do
      expect(value('<property name="p" type="float" value="2.5"/>')).to eq(2.5)
    end

    it 'reads a bool as true or false, never a String' do
      props = parse('<property name="on" type="bool" value="true"/><property name="off" type="bool" value="false"/>')

      expect([props['on'], props['off']]).to eq([true, false])
    end

    it 'reads #AARRGGBB with alpha first' do
      expect(value('<property name="p" type="color" value="#80102030"/>'))
        .to eq(RGame::Util::Color.new(0x10, 0x20, 0x30, 0x80))
    end

    it 'reads #RRGGBB as opaque' do
      expect(value('<property name="p" type="color" value="#102030"/>'))
        .to eq(RGame::Util::Color.new(0x10, 0x20, 0x30, 255))
    end

    it 'reads a colour Tiled left unset as nil' do
      expect(value('<property name="p" type="color" value=""/>')).to be_nil
    end

    it 'keeps an object property as its Integer id' do
      expect(value('<property name="p" type="object" value="12"/>')).to eq(12)
    end
  end

  describe 'a file property' do
    it 'resolves relative to the file that named it' do
      expect(value('<property name="p" type="file" value="../tiles.png"/>', source_path: 'maps/town/level.tmx'))
        .to eq('maps/town/../tiles.png')
    end

    it 'stays as written with no source path' do
      expect(value('<property name="p" type="file" value="../tiles.png"/>')).to eq('../tiles.png')
    end

    it 'keeps an absolute path' do
      absolute = File.expand_path('/srv/tiles.png')

      expect(value(%(<property name="p" type="file" value="#{absolute}"/>), source_path: 'maps/level.tmx'))
        .to eq(absolute)
    end
  end

  describe 'a class property' do
    let(:props) do
      parse(<<~XML, source_path: 'maps/level.tmx')
        <property name="enemy" type="class" propertytype="Enemy">
          <properties>
            <property name="hp" type="int" value="3"/>
            <property name="loot" type="class" propertytype="Loot">
              <properties>
                <property name="gold" type="int" value="5"/>
                <property name="icon" type="file" value="coin.png"/>
              </properties>
            </property>
          </properties>
        </property>
      XML
    end

    it 'nests a Properties, two deep' do
      expect(props['enemy']['loot'].fetch('gold')).to eq(5)
    end

    it 'resolves a nested file against the same source' do
      expect(props['enemy']['loot']['icon']).to eq('maps/coin.png')
    end

    it 'reads a class with every member at its default as EMPTY' do
      expect(value('<property name="p" type="class" propertytype="Enemy"/>')).to be(RGame::Engine::Properties::EMPTY)
    end
  end

  describe 'a value rgame cannot read' do
    it 'raises on an unknown type, naming the property and the type' do
      expect { parse('<property name="p" type="vector" value="1,2"/>') }
        .to raise_error(RGame::Engine::Tiled::FormatError, /'p'.*'vector'/)
    end

    it 'names the file when it knows it' do
      expect { parse('<property name="p" type="int" value="many"/>', source_path: 'level.tmx') }
        .to raise_error(RGame::Engine::Tiled::FormatError, /'p' in level\.tmx/)
    end

    it 'raises on a bool that is neither true nor false' do
      expect { parse('<property name="p" type="bool" value="yes"/>') }
        .to raise_error(RGame::Engine::Tiled::FormatError, /'p'/)
    end

    it 'raises on a malformed colour' do
      expect { parse('<property name="p" type="color" value="red"/>') }
        .to raise_error(RGame::Engine::Tiled::FormatError, /'p'/)
    end
  end

  describe 'reading' do
    let(:body) { '<property name="above" type="bool" value="true"/><property name="n" type="int" value="1"/>' }
    let(:props) { parse(body) }

    it 'answers key?' do
      expect([props.key?('above'), props.key?('spawn')]).to eq([true, false])
    end

    it 'returns the default from fetch when the property is missing' do
      expect(props.fetch('speed', 1.5)).to eq(1.5)
    end

    it 'raises from fetch without a default, naming the property and what there is' do
      expect { props.fetch('speed') }.to raise_error(KeyError, /'speed'.*above, n/)
    end

    it 'enumerates name and value pairs' do
      expect(props.map { |name, v| [name, v] }).to eq([['above', true], ['n', 1]])
    end

    it 'converts to a frozen Hash' do
      expect(props.to_h).to eq({ 'above' => true, 'n' => 1 }).and be_frozen
    end

    it 'is frozen' do
      expect(props).to be_frozen
    end

    it 'equals another bag with the same values' do
      expect(props).to eq(parse(body))
    end
  end
end
