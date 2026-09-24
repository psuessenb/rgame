# frozen_string_literal: true

# Guards the two TileMap reads a running game makes per cell: the renderer asks
# #frame_tile for every animated tile in view on every frame, and a mover asks
# #solid_tile? for every cell its box touches. Each is measured on every branch,
# because leaving a block early allocates and only some answers leave early.
RSpec.describe RGame::Engine::TileMap do
  let(:solid_shape) { '<objectgroup><object x="0" y="0" width="16" height="16"/></objectgroup>' }
  let(:animation) do
    '<animation><frame tileid="0" duration="100"/><frame tileid="1" duration="250"/>' \
      '<frame tileid="2" duration="50"/></animation>'
  end

  let(:map) do
    tmx = <<~TMX
      <map orientation="orthogonal" width="2" height="2" tilewidth="16" tileheight="16">
        <tileset firstgid="1" name="terrain" tilewidth="16" tileheight="16" tilecount="4" columns="2">
          <image source="terrain.png" width="32" height="32"/>
          <tile id="0">#{animation}</tile>
          <tile id="2">#{solid_shape}</tile>
        </tileset>
        #{layer('ground', [1, 0, 0, 0])}
        #{layer('walls', [0, 3, 0, 0])}
      </map>
    TMX
    described_class.from_tiled(RGame::Engine::Tiled::Map.parse(tmx))
  end

  def layer(name, gids)
    %(<layer name="#{name}" width="2" height="2">#{TiledFixture.data(gids, encoding: :csv)}</layer>)
  end

  it 'picks the frame showing without allocating, whichever frame it is' do
    expect { map.frame_tile(1, 0.05) + map.frame_tile(1, 0.2) + map.frame_tile(1, 0.38) + map.frame_tile(2, 0.2) }
      .to allocate_nothing
  end

  it 'answers whether a cell is solid without allocating, solid or open' do
    expect { map.solid_tile?(1, 0) | map.solid_tile?(0, 1) | map.solid_tile?(-1, 0) }.to allocate_nothing
  end
end
