# frozen_string_literal: true

require 'rexml/document'

RSpec.describe RGame::Engine::Tiled::Object do
  def parse(xml, source_path: nil) = described_class.parse(REXML::Document.new(xml).root, source_path: source_path)

  it 'reads a bare rectangle with every number at its default' do
    object = parse('<object id="4"/>')

    expect([object.id, object.shape, object.x, object.y, object.width, object.height, object.rotation])
      .to eq([4, :rectangle, 0.0, 0.0, 0.0, 0.0, 0.0])
  end

  it 'reads name, rotation and visibility' do
    object = parse('<object id="1" name="door" rotation="90" visible="0"/>')

    expect([object.name, object.rotation, object.visible?]).to eq(['door', 90.0, false])
  end

  it 'is visible unless the file says otherwise' do
    expect(parse('<object id="1"/>')).to be_visible
  end

  it 'keeps a tile object at the bottom-left origin the file states, with its gid flip bits and all' do
    object = parse('<object id="1" gid="2147483653" x="32" y="48" width="16" height="16"/>')

    expect([object.gid, object.x, object.y]).to eq([2_147_483_653, 32.0, 48.0])
  end

  it 'has no gid when it is a shape' do
    expect(parse('<object id="1"/>').gid).to be_nil
  end

  %w[point ellipse text].each do |kind|
    it "reads a #{kind}, with no points" do
      object = parse(%(<object id="1"><#{kind}/></object>))

      expect([object.shape, object.points]).to eq([kind.to_sym, []])
    end
  end

  it 'reads a capsule with its width and height, as it reads an ellipse' do
    # Tiled 1.12 added the capsule. Before rgame knew it, a capsule read as a
    # rectangle of the same size, and nothing said so.
    object = parse('<object id="4" x="153" y="193" width="56" height="25"><capsule/></object>')

    expect([object.shape, object.width, object.height, object.points]).to eq([:capsule, 56.0, 25.0, []])
  end

  it 'reads a rectangle with properties as a rectangle' do
    object = parse('<object id="1" width="8" height="8"><properties><property name="p"/></properties></object>')

    expect(object.shape).to eq(:rectangle)
  end

  it 'reads the shape that follows its properties' do
    expect(parse('<object id="1"><properties><property name="p"/></properties><point/></object>').shape)
      .to eq(:point)
  end

  it 'raises on a child that is no shape it knows, naming the element, the object and the file' do
    expect { parse('<object id="4" width="8" height="8"><banana/></object>', source_path: 'level.tmx') }
      .to raise_error(RGame::Engine::Tiled::FormatError, /object 4 in level\.tmx has a <banana>/)
  end

  it 'reads a polyline as pairs relative to the object' do
    expect(parse('<object id="1" x="10" y="10"><polyline points="0,0 -4,6.5"/></object>').points)
      .to eq([[0.0, 0.0], [-4.0, 6.5]])
  end

  it 'raises on points that are not x,y pairs, naming the file' do
    expect { parse('<object id="1"><polygon points="0,0 4"/></object>', source_path: 'level.tmx') }
      .to raise_error(RGame::Engine::Tiled::FormatError, /<polygon> in level\.tmx.*points/)
  end

  it 'raises on a coordinate that is not a number' do
    expect { parse('<object id="1" x="left"/>') }
      .to raise_error(RGame::Engine::Tiled::FormatError, /x="left"/)
  end
end
