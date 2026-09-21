# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'tmpdir'

# `RGame::Game`'s `:tilemap` loader: a `.tmx` read, built into a map, and its
# tilesets cut into one flat Array of images indexed by tile id.
#
# `Game` names Engine, and this suite may not load it, so the game is built in
# a child process — see game_locales_spec.rb. The child answers what the loader
# handed `TileMapRenderer`: one `[class, width, height]` per tile id.
RSpec.describe 'RGame::Game tile map loader' do # rubocop:disable RSpec/DescribeClass -- the subject is Game, which this suite may not load
  let(:media) { Dir.mktmpdir }

  after { FileUtils.remove_entry(media) }

  def png(name, width, height)
    FileUtils.cp(PngFixture.write(width, height) { [255, 255, 255, 255] }, File.join(media, name))
  end

  def tmx(tilesets)
    File.write(File.join(media, 'map.tmx'), <<~TMX)
      <map orientation="orthogonal" width="2" height="1" tilewidth="16" tileheight="16">
        #{tilesets}
        <layer name="ground" width="2" height="1"><data encoding="csv">1,2</data></layer>
      </map>
    TMX
  end

  def loaded_tiles
    script = <<~RUBY
      require 'rgame/game'
      require 'json'

      game = RGame::Game.new(root: RGame::Engine::Node2D.new, width: 64, height: 48,
                             caption: 'tile map loader spec', media_root: #{media.inspect})
      tiles = game.assets.tilemap('map.tmx').instance_variable_get(:@tiles)
      game.close
      puts JSON.generate(tiles.map { it && [it.class.name, it.width, it.height] })
    RUBY
    output, errors, status = ChildRuby.capture(script)
    raise "child failed (#{status}):\n#{output}#{errors}" unless status.success?

    JSON.parse(output.lines.last)
  end

  it 'cuts a sheet with a margin and spacing into its tiles' do
    # 1 px of margin and 2 px of spacing around three 16 px tiles in a row.
    png('sheet.png', 54, 18)
    tmx(<<~XML)
      <tileset firstgid="1" name="sheet" tilewidth="16" tileheight="16" margin="1" spacing="2"
               tilecount="3" columns="3"><image source="sheet.png" width="54" height="18"/></tileset>
    XML

    expect(loaded_tiles).to eq([nil, *Array.new(3, ['RGame::Core::Image', 16, 16])])
  end

  # The renderer takes one Array of images however the tileset stored them, so
  # a collection comes out in the same shape as a sheet, in tile-id order.
  it 'loads a collection of images into the same flat Array as a sheet' do
    png('tree.png', 16, 32)
    png('rock.png', 16, 16)
    tmx(<<~XML)
      <tileset firstgid="1" name="props" tilewidth="16" tileheight="32" tilecount="2" columns="0">
        <tile id="0"><image source="tree.png" width="16" height="32"/></tile>
        <tile id="1"><image source="rock.png" width="16" height="16"/></tile>
      </tileset>
    XML

    expect(loaded_tiles).to eq([nil, ['RGame::Core::Image', 16, 32], ['RGame::Core::Image', 16, 16]])
  end
end
