# frozen_string_literal: true

# The shipped example assets, checked against what the engine actually asks of
# them.
#
# These files are data, so nothing type-checks them and nothing fails to compile
# when one drifts. A misspelt animation key in hero.json is a `KeyError` out of
# AnimationSet on the first frame the hero faces that way — at runtime, in a
# window, in whichever example happens to walk left first. A re-exported PNG one
# row short is a frame sliced out of empty space, which draws nothing and raises
# nothing at all.
#
# Both are cheap to catch here: the descriptor is JSON, AnimationSet is pure
# Engine, and a PNG's dimensions are in the first 24 bytes. No window, no Core.

require 'json'

RSpec.describe 'examples/assets' do # rubocop:disable RSpec/DescribeClass -- the subject is shipped data, not a class
  let(:assets) { File.expand_path('../examples/assets', __dir__) }

  describe 'hero.json' do
    subject(:animations) { RGame::Engine::AnimationSet.new(descriptor[:animations]) }

    let(:descriptor) { JSON.parse(File.read(File.join(assets, 'hero.json')), symbolize_names: true) }

    # The names are not ours to choose: Components::AnimatedSprite picks one of
    # these five from the body's movement intent and looks it up by name, and
    # AnimationSet#row uses `fetch`. A sheet missing one is a crash the moment a
    # player walks that way.
    %i[stand walk_up walk_down walk_left walk_right].each do |name|
      it "declares #{name}, which AnimatedSprite resolves by name" do
        expect { animations.row(name) }.not_to raise_error
      end
    end

    it 'mirrors walk_left off the walk_right row rather than repeating the art' do
      # Every left frame in the source was a pixel-exact mirror of its right
      # counterpart, so the sheet ships three rows and flips one. If a future
      # sheet draws left properly, this example is the thing to delete — but it
      # should be deleted deliberately, not silently stop being true.
      expect(animations.row(:walk_left)).to eq(animations.row(:walk_right))
      expect(animations.flip_x(:walk_left)).to be(true)
      expect(animations.flip_x(:walk_right)).to be(false)
    end

    it 'cycles every walk through all six frames' do
      %i[walk_up walk_down walk_left walk_right].each do |name|
        columns = (0...6).map { |i| animations.col(name, i * 0.125) }

        expect(columns).to eq([0, 1, 2, 3, 4, 5])
      end
    end

    it 'holds stand on one frame' do
      expect((0..5).map { |i| animations.col(:stand, i * 0.5) }.uniq).to eq([0])
    end

    it 'fits every frame inside hero.png' do
      # The guard against a re-export at a different size. Frames are sliced by
      # arithmetic, so a row past the bottom edge is not an error anywhere — it
      # is a sprite that draws nothing.
      width, height = png_size(File.join(assets, descriptor[:image]))
      rows = descriptor[:animations].values.map { |a| a[:row] }.max + 1
      columns = descriptor[:animations].values.map { |a| (a[:col] || 0) + a[:frames] }.max

      expect(columns * descriptor[:frame_width]).to be <= width
      expect(rows * descriptor[:frame_height]).to be <= height
    end
  end

  describe 'ui.json' do
    subject(:elements) { descriptor[:nine_slices] }

    let(:descriptor) { JSON.parse(File.read(File.join(assets, 'ui.json')), symbolize_names: true) }

    # UI::PanelButton draws one of these four by state, and a nine-slice id is
    # resolved by *registration* only — it is an element name, never a file — so
    # a missing one is a KeyError out of the renderer the first time an item
    # reaches that state. The disabled and pressed ones are the nasty pair: a
    # menu can run for a long time before either is drawn.
    it 'declares every element UI::PanelButton draws, plus the panel' do
      required = RGame::Engine::UI::PanelButton::STYLE.elements.values.map(&:to_sym) + [:panel]

      expect(elements.keys).to include(*required)
    end

    it 'keeps every element inside ui.png' do
      width, height = png_size(File.join(assets, descriptor[:image]))

      elements.each_value do |e|
        expect(e[:x] + e[:w]).to be <= width
        expect(e[:y] + e[:h]).to be <= height
      end
    end

    it 'leaves a middle for every element to stretch' do
      # A nine-slice cuts `border` off each side; borders meeting in the middle
      # leave nothing to tile and the widget draws as corners alone.
      elements.each_value do |e|
        expect(e[:border] * 2).to be < e[:w]
        expect(e[:border] * 2).to be < e[:h]
      end
    end
  end

  describe 'icons.json' do
    subject(:images) { descriptor[:images] }

    let(:descriptor) { JSON.parse(File.read(File.join(assets, 'icons.json')), symbolize_names: true) }

    # An icon is cut with Image#subimage when the atlas loads, which raises for
    # a rectangle off the sheet — but only in a window, where nothing in this
    # suite runs. Checked here instead, against the PNG's own header.
    it 'cuts every image from inside icons.png' do
      width, height = png_size(File.join(assets, descriptor[:image]))

      images.each_value do |rect|
        expect(rect[:x] + rect[:w]).to be <= width
        expect(rect[:y] + rect[:h]).to be <= height
      end
    end

    # An image id is resolved by registration, so an icon the example names and
    # the atlas does not declare is a KeyError on the first frame the wheel is
    # drawn.
    %w[radial_menu quick_wheel].each do |example|
      it "declares every icon examples/#{example} names" do
        source = File.read(File.expand_path("../examples/#{example}/main.rb", __dir__))
        # Anchored at the start of a line, so the header's prose cannot be read
        # as the table.
        table = source[/^\s*ICONS = \[(.+?)\]\.freeze/m, 1]
        # Each row is `%i[key image]`: the translation key, then the icon.
        named = table.scan(/%i\[\w+ (\w+)\]/).flatten.map(&:to_sym)

        expect(named.size).to eq(8)
        expect(images.keys).to include(*named)
      end
    end
  end

  describe 'skills.json' do
    subject(:images) { descriptor[:images] }

    let(:descriptor) { JSON.parse(File.read(File.join(assets, 'skills.json')), symbolize_names: true) }

    # The same check as icons.json's: a rectangle off the sheet raises only in a
    # window, where nothing in this suite runs.
    it 'cuts every image from inside skills.png' do
      width, height = png_size(File.join(assets, descriptor[:image]))

      images.each_value do |rect|
        expect(rect[:x] + rect[:w]).to be <= width
        expect(rect[:y] + rect[:h]).to be <= height
      end
    end

    it 'declares every tool examples/skill_bar names' do
      source = File.read(File.expand_path('../examples/skill_bar/main.rb', __dir__))
      # Anchored at the start of a line, so the header's prose cannot be read
      # as the table.
      table = source[/^\s*SKILLS = \[(.+?)\]\.freeze/m, 1]
      # Each row is `%i[key image hotkey]`: the image is the second word.
      named = table.scan(/%i\[\w+ (\w+) \w+\]/).flatten.map(&:to_sym)

      expect(named.size).to eq(5)
      expect(images.keys).to include(*named)
    end
  end

  describe 'glyphs.json' do
    subject(:descriptor) { JSON.parse(File.read(File.join(assets, 'glyphs.json')), symbolize_names: true) }

    # The sheet and examples/input_glyphs are two halves of one table: the
    # example maps a button id to a column, and only this file says what is in
    # that column. Neither half can check the other at runtime — a column past
    # the end of the strip is sliced out of empty space, draws nothing and
    # raises nothing, which looks exactly like an action nobody bound.
    let(:columns) do
      source = File.read(File.expand_path('../examples/input_glyphs/main.rb', __dir__))
      # Anchored at the start of a line: the file's own header quotes the table
      # in prose, and an unanchored match reads the comment instead.
      table = source[/^\s*GLYPH_COLUMN = \{(.+?)\}\.freeze/m, 1]
      table.scan(/Controls::(\w+)\s*=>\s*(\d+)/).to_h { |name, column| [name, Integer(column)] }
    end

    it 'has a frame for every column the example names' do
      width, height = png_size(File.join(assets, descriptor[:image]))
      frames = width / descriptor[:frame_width]

      expect(columns.values).to all(be < frames)
      expect(descriptor[:frame_height]).to eq(height)
    end

    it 'names five buttons, and every one of them is a real id' do
      expect(columns.size).to eq(5)
      expect(columns.keys.map { |name| RGame::Util::Controls.const_get(name) }).to all(be_an(Integer))
    end

    # The two id spaces are what the whole example turns on, so the sheet's own
    # ordering is checked against them: the keyboard glyphs come first and the
    # pad glyphs after, and a key filed under a pad column would put a face
    # button on a keyboard prompt.
    it 'groups the keyboard glyphs before the pad ones' do
      controls = RGame::Util::Controls
      pad_columns, key_columns = columns.partition { |name, _| controls.pad_button?(controls.const_get(name)) }
                                        .map { |group| group.map(&:last) }

      expect(key_columns.max).to be < pad_columns.min
    end
  end

  describe 'the audio' do
    # The engine plays Ogg Vorbis and WAV, and nothing else: MP3 and FLAC are
    # compiled out of miniaudio (ext/rgame_core/vendor/miniaudio_impl.c) to save
    # object code and parser surface. So dropping in an .mp3 that plays fine in
    # every desktop player fails at load, on whatever machine first runs the
    # example. The magic bytes are cheap to check and this suite has no decoder.
    %w[music.ogg blip.ogg].each do |name|
      it "ships #{name} as Ogg Vorbis, which is a format the engine can play" do
        header = File.binread(File.join(assets, name), 64)

        expect(header[0, 4]).to eq('OggS')
        expect(header).to include('vorbis')
      end
    end

    it 'matches the loop length examples/music draws its playhead against' do
      # examples/music has to state the loop length as a constant — nothing can
      # ask a Song how long it is — so the constant and the file are two copies
      # of one fact, free to drift the moment the track is replaced. It was
      # replaced once already.
      source = File.read(File.expand_path('../examples/music/main.rb', __dir__))
      declared = source[/^\s*LOOP_SECONDS\s*=\s*([0-9.]+)/, 1].to_f

      expect(ogg_seconds(File.join(assets, 'music.ogg'))).to be_within(0.05).of(declared)
    end

    it 'keeps the music mono, which is what makes it small enough to ship' do
      # Re-exported in stereo it is five times the size, and it is background
      # music in an example — see tools/shrink_ogg.c and the asset README.
      expect(vorbis_channels(File.join(assets, 'music.ogg'))).to eq(1)
    end
  end

  describe 'town.tmx' do
    subject(:map) do
      RGame::Engine::TileMap.from_tiled(RGame::Engine::Tiled::Map.load(File.join(assets, 'town.tmx')))
    end

    let(:fence_row) { 20 }
    let(:gap) { 12..14 }
    let(:north) { [45, 8] }
    let(:south) { [45, 30] }

    it 'is larger than the window on both axes, so there is something to scroll' do
      # A map that fits on screen makes examples/scroll_map a still image:
      # Camera#resolve pins a camera to the origin when the world is smaller
      # than the view, so the failure is a scrolling example that does not.
      # 640x480 is the window every example opens. Written out rather than read
      # off RGame::Game, which lives behind rgame/core and is an undefined
      # constant in this suite by design.
      expect(map.pixel_width).to be > 640
      expect(map.pixel_height).to be > 480
    end

    it 'has exactly one gap in the fence, where the map says it is' do
      # The mistake this catches was made once already: a fence stopping a tile
      # short of the border leaves a second gap nobody planned, and the route
      # quietly uses that one instead of the intended one.
      open_tiles = (0...map.width).reject { |col| map.solid_tile?(col, fence_row) }

      expect(open_tiles).to eq(gap.to_a)
    end

    it 'starts and ends the route on walkable tiles' do
      expect(map.solid_tile?(*north)).to be(false)
      expect(map.solid_tile?(*south)).to be(false)
    end

    it 'forces a route far longer than the straight line between the clearings' do
      # The other mistake made once: with the gap sitting between start and
      # goal, the shortest route cost exactly the straight-line distance and a
      # pathfinder had nothing to show. This is what examples/pathfinding needs
      # from the map, so it is asserted rather than admired.
      steps = shortest_route(map, north, south)
      straight = (south[0] - north[0]).abs + (south[1] - north[1]).abs

      expect(steps).not_to be_nil, 'the two clearings are not connected at all'
      expect(steps).to be > straight * 2
    end
  end

  # A gap is a tile's class in Tiled, and nothing else says so: a pit tile that
  # lost its class draws a hole the hero walks straight over.
  describe 'pits.tsx and pits.tmx' do
    let(:map) { RGame::Engine::TileMap.from_tiled(RGame::Engine::Tiled::Map.load(File.join(assets, 'pits.tmx'))) }

    it 'makes every tile in pits.tsx a gap' do
      tileset = RGame::Engine::Tiled::Tileset.load(File.join(assets, 'pits.tsx'))

      classes = (0...tileset.tile_count).map { tileset.tile(it)&.class_name }

      expect(classes).to all(eq(RGame::Engine::TileMap::GAP))
    end

    it 'has gaps, and a start standing on floor' do
      start = map.object_named('start')
      col = map.col_at(start.x)
      row = map.row_at(start.y - 1)

      expect(map.gap_tile?(12, 10)).to be(true)
      expect([map.gap_tile?(col, row), map.solid_tile?(col, row)]).to eq([false, false])
    end
  end

  # The raft never touches a bank, and a hop from either bank reaches it at the
  # end of its route: that gap is the whole point of examples/moving_platforms.
  describe 'platforms.tmx' do
    let(:map) { RGame::Engine::TileMap.from_tiled(RGame::Engine::Tiled::Map.load(File.join(assets, 'platforms.tmx'))) }
    let(:raft) { map.objects.find { it.class_name == 'Raft' } }
    let(:hop) { 40 }

    # Where the chasm's floor ends on each side of the raft's row, in pixels.
    def banks
      row = map.row_at(raft.y)
      gaps = (0...map.width).select { map.gap_tile?(it, row) }
      [map.cell_x(gaps.min), map.cell_x(gaps.max + 1)]
    end

    it 'has a start standing on floor' do
      start = map.object_named('start')
      expect(map.gap_tile?(map.col_at(start.x), map.row_at(start.y - 1))).to be(false)
    end

    it 'stops each end of the raft’s route short of its bank by less than a hop' do
      route = RGame::Engine::Path.from_object(raft)
      half = raft.properties.fetch('deck_width') / 2.0
      west, east = banks
      gaps = [route.x_at(0) - half - west, east - (route.x_at(1) + half)]
      expect(gaps).to all(be_between(1, hop - 1))
    end
  end

  describe 'tiles.json' do
    let(:descriptor) { JSON.parse(File.read(File.join(assets, 'tiles.json')), symbolize_names: true) }

    it 'cuts tileset.png into whole 16x16 tiles, with no animations' do
      width, height = png_size(File.join(assets, descriptor[:image]))
      expect([width % descriptor[:frame_width], height % descriptor[:frame_height], descriptor[:animations]])
        .to eq([0, 0, nil])
    end
  end

  # The doors between the town and the garden live in the maps, so a designer
  # who moves one in Tiled can break a room nobody has walked into yet. These
  # hold the files themselves, before any example runs. Each map is keyed by the
  # room built over it, as examples/doors defines its rooms.
  describe 'the doors in town_with_gate.tmx and garden.tmx' do
    let(:maps) { { 'town' => loaded('town_with_gate.tmx'), 'garden' => loaded('garden.tmx') } }

    # How far a feet box reaches from the point a node stands on: half a hero's
    # 12 px width, rounded up to half a tile.
    let(:reach) { 8 }

    def loaded(file) = RGame::Engine::TileMap.from_tiled(RGame::Engine::Tiled::Map.load(File.join(assets, file)))

    # Every tile layer's name, visibility and cells, in the map's order.
    def tile_layers(map)
      layers = (0...map.layer_count).map { map.layer(it) }.select { it.kind == :tile }
      layers.map do |layer|
        cells = (0...map.height).flat_map { |row| (0...map.width).map { |col| map.tile(layer.index, col, row) } }
        [layer.path, layer.visible?, layer.opacity, layer.above?, cells]
      end
    end

    def all_of(class_names)
      maps.flat_map { |room, map| map.objects.select { class_names.include?(it.class_name) }.map { [room, it] } }
    end

    it 'gives the gated town the tile layers of town.tmx, cell for cell, so an edit to one is an edit to both' do
      expect(tile_layers(maps['town'])).to eq(tile_layers(loaded('town.tmx')))
    end

    it 'leaves town.tmx with no class that builds, since five examples mount it and define no Door' do
      expect(loaded('town.tmx').objects.map(&:class_name).grep(/\A[[:upper:]]/)).to be_empty
    end

    it 'loads the garden, the size of the window' do
      expect([maps['garden'].pixel_width, maps['garden'].pixel_height]).to eq([640, 480])
    end

    it "names, on every Door and Warp, an entrance on the map the door's to names" do
      targets = all_of(%w[Door Warp]).map do |room, door|
        to = door.class_name == 'Warp' ? room : door.properties.fetch('to')
        maps.fetch(to).object_named(door.properties.fetch('entrance')).class_name
      end

      expect(targets).to all(eq('entrance')).and have_attributes(size: 5)
    end

    it "puts every entrance off every door's and pad's box, so nobody arrives on one" do
      on_a_door = all_of(%w[entrance]).select do |room, entrance|
        maps[room].objects.select { %w[Door Warp].include?(it.class_name) }.any? do |door|
          entrance.x.between?(door.x - reach, door.x + door.width + reach) &&
            entrance.y.between?(door.y - reach, door.y + door.height + reach)
        end
      end

      expect(on_a_door.map { |room, entrance| "#{room} #{entrance.name}" }).to be_empty
    end

    it 'puts every entrance and every door on walkable ground' do
      blocked = all_of(%w[entrance Door Warp]).select do |room, object|
        [[object.x, object.y], [object.x + object.width, object.y + object.height]].any? do |x, y|
          maps[room].solid_at?(x, [y - 1, object.y].max)
        end
      end

      expect(blocked.map { |room, object| "#{room} #{object.name}" }).to be_empty
    end
  end

  # Breadth-first over the walkable tiles: how many steps the shortest route
  # takes, or nil if there is none. Deliberately not A* — this states what the
  # map guarantees without depending on the algorithm the example under test
  # will use to find it.
  def shortest_route(map, from, to)
    # Bound once rather than written inside the loop, which would rebuild it per
    # tile visited.
    neighbours = [[1, 0], [-1, 0], [0, 1], [0, -1]].freeze
    distance = { from => 0 }
    queue = [from]
    until queue.empty?
      col, row = queue.shift
      return distance[[col, row]] if [col, row] == to

      neighbours.each do |d_col, d_row|
        step = [col + d_col, row + d_row]
        next if distance.key?(step)
        next unless step[0].between?(0, map.width - 1) && step[1].between?(0, map.height - 1)
        next if map.solid_tile?(*step)

        distance[step] = distance[[col, row]] + 1
        queue << step
      end
    end
    nil
  end

  # Length in seconds: the last Ogg page's granule position is the total sample
  # count, and the sample rate is in the identification header. Read here rather
  # than decoded, so this suite stays headless.
  def ogg_seconds(path)
    data = File.binread(path)
    header = data.index("\x01vorbis")
    rate = data[header + 12, 4].unpack1('V')
    granule = data[data.rindex('OggS') + 6, 8].unpack1('q<')
    granule.to_f / rate
  end

  # Channel count from the Vorbis identification header, which follows the
  # `\x01vorbis` marker in the first Ogg page: one byte of version-and-channels
  # layout where the channel count sits at offset 11.
  def vorbis_channels(path)
    data = File.binread(path, 128)
    data.getbyte(data.index("\x01vorbis") + 11)
  end

  # A PNG opens with an 8-byte signature and then the IHDR chunk, whose first
  # two fields are width and height as big-endian uint32 at offsets 16 and 20.
  # Reading them here rather than loading the image keeps this suite headless —
  # RGame::Core::Image would pull in SDL and is an undefined constant in this
  # process by design.
  def png_size(path)
    File.binread(path, 24).unpack('@16 N2')
  end
end
