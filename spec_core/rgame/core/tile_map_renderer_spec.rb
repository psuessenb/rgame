# frozen_string_literal: true

# Driven entirely by StubTileMap and FakeRenderer. What a tile map renderer gets
# wrong is which tiles it draws and where — a layer mixed up, a tile one column
# off, a bake repeated every frame — and recorded calls state that exactly,
# where a rendered frame would only say the map looks odd.
#
# The map it is handed is checked against the same 'a tile map' contract as the
# real parsed one, in spec/, so a stand-in that had drifted would fail there
# rather than quietly passing here.
RSpec.describe RGame::Core::TileMapRenderer do
  let(:renderer) { FakeRenderer.new }

  # Tile images identifiable by tile id, so a drawn tile says which one it was.
  let(:tiles) { Array.new(8) { |index| StubImage.new(16, 16, region: [index, 0, 16, 16]) } }

  # 2x2, two layers. Layer 0 has three tiles, layer 1 has one.
  def two_layer_map(animations: {})
    StubTileMap.new(layers: [[1, 2, 0, 3], [0, 0, 4, 0]], above: [false, true], animations: animations)
  end

  # The tile ids baked into the recording the last draw replayed.
  def baked_ids
    recording = renderer.calls_to(:recording_draw).last.args.first
    recording.calls_to(:image_at).map { |call| call.args.first.region.first }
  end

  # Every call baked into the recording the last draw replayed.
  def baked_calls = renderer.calls_to(:recording_draw).last.args.first.calls

  # The tile ids drawn straight into the frame, outside any recording.
  def drawn_ids = renderer.calls_to(:image_at).map { |call| call.args.first.region.first }

  describe 'one layer at a time' do
    it 'bakes only that layer' do
      described_class.new(two_layer_map, tiles).draw_layer(renderer, 0, 0, 0, 64, 64)

      # Layer 0 holds tiles 1, 2 and 3. Layer 1's tile 4 belongs to another
      # node and must not appear.
      expect(baked_ids).to contain_exactly(1, 2, 3)
    end

    it 'bakes the next layer on its own too' do
      described_class.new(two_layer_map, tiles).draw_layer(renderer, 1, 0, 0, 64, 64)

      expect(baked_ids).to eq([4])
    end

    it 'draws an empty layer as an empty recording rather than refusing' do
      # A spacer layer in Tiled is ordinary, and every layer index has to keep
      # meaning the same thing — skipping one would shift all the rest.
      map = StubTileMap.new(layers: [[0, 0, 0, 0]])
      described_class.new(map, tiles).draw_layer(renderer, 0, 0, 0, 64, 64)

      expect(baked_ids).to be_empty
      expect(renderer.calls_to(:recording_draw).length).to eq(1)
    end

    it 'refuses a layer the map does not have' do
      expect { described_class.new(two_layer_map, tiles).draw_layer(renderer, 2, 0, 0, 64, 64) }
        .to raise_error(ArgumentError, /no layer 2/)
    end

    it 'skips empty tiles' do
      # Tile 0 is "nothing here". Drawing it would put whatever sits at index 0
      # of the images across every hole in the map.
      described_class.new(two_layer_map, tiles).draw_layer(renderer, 0, 0, 0, 64, 64)

      expect(baked_ids.length).to eq(3)
    end
  end

  describe 'baking' do
    it 'places each tile at its own grid position' do
      described_class.new(two_layer_map, tiles).draw_layer(renderer, 0, 0, 0, 64, 64)

      recording = renderer.calls_to(:recording_draw).last.args.first
      expect(recording.calls_to(:image_at).map { |call| call.args[1..] })
        .to eq([[0, 0], [16, 0], [16, 16]])
    end

    it 'bakes once and replays thereafter' do
      # The bug this class exists to avoid: rebaking every frame turns one call
      # per texture back into one per tile, and nothing shows it but the frame
      # rate.
      map = described_class.new(two_layer_map, tiles)
      3.times { map.draw_layer(renderer, 0, 0, 0, 64, 64) }

      replays = renderer.calls_to(:recording_draw)
      expect(replays.length).to eq(3)
      # The same recording all three times. Counting replays alone would not
      # say it: a rebake replays too, it just throws the last one away.
      expect(replays.map { |call| call.args.first }.uniq.length).to eq(1)
    end

    it 'keeps each layer baked separately' do
      map = described_class.new(two_layer_map, tiles)
      map.draw_layer(renderer, 0, 0, 0, 64, 64)
      ground = renderer.calls_to(:recording_draw).last.args.first
      map.draw_layer(renderer, 1, 0, 0, 64, 64)
      canopy = renderer.calls_to(:recording_draw).last.args.first

      expect(canopy).not_to equal(ground)
    end

    # The map draws where its tiles live and the caller's transform puts them on
    # screen, so the replay carries no offset at all — which is what makes one
    # bake serve every viewport rather than only the camera it was baked for.
    it 'replays the layer at its own origin, whatever the cull rect' do
      described_class.new(two_layer_map, tiles).draw_layer(renderer, 0, 48, 32, 64, 64)

      expect(renderer.calls_to(:recording_draw).last.args[1..]).to eq([0, 0])
    end

    # No z anywhere in here. A layer is drawn by a node of its own, so where it
    # sits among the actors is the scene tree's answer rather than a number this
    # class or its caller picks.
    it 'replays at the layer base, taking no z of its own' do
      described_class.new(two_layer_map, tiles).draw_layer(renderer, 0, 0, 0, 64, 64)

      expect(renderer.calls_to(:recording_draw).last.options[:z]).to be_zero
    end
  end

  describe 'animated tiles' do
    let(:animations) { { 1 => [[1, 0.1], [2, 0.1]] } }

    it 'leaves them out of the bake' do
      described_class.new(two_layer_map(animations: animations), tiles)
                     .draw_layer(renderer, 0, 0, 0, 64, 64)

      # Tile 1 is animated; 2 and 3 are not.
      expect(baked_ids).to contain_exactly(2, 3)
    end

    it 'draws them into the frame instead, at their world position' do
      described_class.new(two_layer_map(animations: animations), tiles)
                     .draw_layer(renderer, 0, 0, 0, 64, 64)

      expect(renderer.calls_to(:image_at).map { |call| call.args[1..] }).to eq([[0, 0]])
    end

    it 'follows elapsed rather than a clock' do
      # Two 0.1 s frames. A spec picks the frame it wants instead of stubbing
      # time.
      map = described_class.new(two_layer_map(animations: animations), tiles)

      map.draw_layer(renderer, 0, 0, 0, 64, 64, elapsed: 0.0)
      map.draw_layer(renderer, 0, 0, 0, 64, 64, elapsed: 0.15)
      map.draw_layer(renderer, 0, 0, 0, 64, 64, elapsed: 0.25)

      expect(drawn_ids).to eq([1, 2, 1])
    end

    it 'stands still when elapsed does not move' do
      # What pausing looks like from here: the same number in, the same frame
      # out, however many times it is drawn.
      map = described_class.new(two_layer_map(animations: animations), tiles)
      3.times { map.draw_layer(renderer, 0, 0, 0, 64, 64, elapsed: 0.15) }

      expect(drawn_ids).to eq([2, 2, 2])
    end

    it 'draws them in world coordinates, like the baked layer' do
      described_class.new(two_layer_map(animations: animations), tiles)
                     .draw_layer(renderer, 0, 8, 4, 64, 64)

      # Column 0, row 0 of a 16px tileset: at the origin, not at -cull.
      expect(renderer.calls_to(:image_at).map { |call| call.args[1..] }).to eq([[0, 0]])
    end

    it 'draws them at the layer base, like the baked tiles beside them' do
      map = StubTileMap.new(layers: [[0, 0, 0, 0], [1, 0, 0, 0]], animations: animations)
      described_class.new(map, tiles).draw_layer(renderer, 1, 0, 0, 64, 64)

      expect(renderer.calls_to(:image_at).first.options[:z]).to be_zero
    end
  end

  describe 'hidden and translucent layers' do
    def map_with(visible: [true, true], opacity: [1.0, 1.0])
      StubTileMap.new(layers: [[1, 2, 0, 3], [0, 0, 4, 0]], visible: visible, opacity: opacity,
                      animations: { 1 => [[1, 0.1], [2, 0.1]] })
    end

    it 'bakes nothing and draws nothing for a hidden layer' do
      described_class.new(map_with(visible: [false, true]), tiles).draw_layer(renderer, 0, 0, 0, 64, 64)

      expect(renderer.calls).to be_empty
    end

    it 'replays an opaque layer untinted' do
      described_class.new(map_with, tiles).draw_layer(renderer, 0, 0, 0, 64, 64)

      expect(renderer.calls_to(:recording_draw).last.options[:color]).to be_nil
    end

    it 'replays a layer at its opacity' do
      described_class.new(map_with(opacity: [0.5, 1.0]), tiles).draw_layer(renderer, 0, 0, 0, 64, 64)

      expect(renderer.calls_to(:recording_draw).last.options[:color]).to eq(RGame::Util::Color.new(255, 255, 255, 128))
    end

    it 'draws the layer\'s animated tiles at the same opacity' do
      described_class.new(map_with(opacity: [0.5, 1.0]), tiles).draw_layer(renderer, 0, 0, 0, 64, 64)

      expect(renderer.calls_to(:image_at).map { it.options[:color] })
        .to eq([RGame::Util::Color.new(255, 255, 255, 128)])
    end
  end

  describe 'a tile of another size than the cell' do
    # Tiled stands a tile on its cell's bottom-left corner, so a tree two cells
    # tall reaches up into the cell above rather than down into the one below.
    it 'stands on the bottom of its cell' do
      tall = [nil, StubImage.new(16, 32)]
      described_class.new(StubTileMap.new(layers: [[1, 0, 0, 0]]), tall).draw_layer(renderer, 0, 0, 0, 64, 64)

      expect(baked_calls.map { it.args[1..] }).to eq([[0, -16]])
    end
  end

  # A tileset's drawing offset in Tiled: every tile of it moves by the same
  # pixels, with y down.
  describe 'a drawing offset' do
    def map_with(orientations: {}, animations: {})
      StubTileMap.new(layers: [[1, 0, 0, 0]], tile_offsets: { 1 => [2, -4], 2 => [5, 6] },
                      orientations: orientations, animations: animations)
    end

    it 'moves a baked tile' do
      described_class.new(map_with, tiles).draw_layer(renderer, 0, 0, 0, 64, 64)

      expect(baked_calls.map { it.args[1..] }).to eq([[2, -4]])
    end

    it 'turns a tile about its moved centre, and does not turn with it' do
      described_class.new(map_with(orientations: { [0, 0, 0] => [1, false] }), tiles)
                     .draw_layer(renderer, 0, 0, 0, 64, 64)

      expect(baked_calls.first.args).to eq([90, 10.0, 4.0])
    end

    it 'moves an animated tile by the offset of the frame it shows' do
      described_class.new(map_with(animations: { 1 => [[1, 0.1], [2, 0.1]] }), tiles)
                     .draw_layer(renderer, 0, 0, 0, 64, 64, elapsed: 0.15)

      expect(renderer.calls_to(:image_at).map { it.args[1..] }).to eq([[5, 6]])
    end

    it 'lands on the pixels it names, through a real window' do
      map = StubTileMap.new(layers: [[1, 0, 0, 0]], tile_offsets: { 1 => [4, 2] })
      frame = RenderedFrame.capture(width: 32, height: 32) do |renderer, app|
        image = RGame::Core::Image.new(app, PngFixture.write(16, 16) { [255, 255, 255, 255] })
        described_class.new(map, [nil, image]).draw_layer(renderer, 0, 0, 0, 32, 32)
      end

      expect([frame.about?(2, 1, [26, 26, 38, 255]), frame.about?(5, 3, [255, 255, 255, 255]),
              frame.about?(19, 17, [255, 255, 255, 255]), frame.about?(21, 17, [26, 26, 38, 255])])
        .to eq([true, true, true, true])
    end
  end

  describe 'turned tiles' do
    def baked_calls_for(orientation, image: tiles[1])
      map = StubTileMap.new(layers: [[1, 0, 0, 0]], orientations: { [0, 0, 0] => orientation })
      described_class.new(map, [nil, image]).draw_layer(renderer, 0, 0, 0, 64, 64)
      baked_calls
    end

    it 'draws a tile that is not turned with no transform' do
      expect(baked_calls_for([0, false]).map(&:name)).to eq([:image_at])
    end

    it 'turns a tile about its own centre' do
      expect(baked_calls_for([1, false]).first.args).to eq([90, 8.0, 8.0])
    end

    it 'mirrors a tile inside its own cell' do
      expect(baked_calls_for([0, true]).last.options[:scale_x]).to eq(-1)
    end

    it 'keeps a turned tile that is not square standing on its cell' do
      # A 16x32 tile turned a quarter is 32 wide and 16 tall, and Tiled keeps
      # its bottom-left corner on the cell's: the centre moves by half the
      # difference of the sides on both axes.
      rotate, draw = baked_calls_for([1, false], image: StubImage.new(16, 32))

      expect([rotate.args, draw.args[1..]]).to eq([[90, 16.0, 8.0], [8.0, -8.0]])
    end
  end

  # spec/fixtures/orientations.tmx, painted in Tiled: an F in each of the eight
  # ways Tiled's stamp turns a tile, in columns 1 to 8. What rgame read from it
  # is pinned in spec/rgame/engine/tile_map_spec.rb; this draws the same eight
  # values and checks every pixel.
  #
  # The expected picture is not rgame's arithmetic. It is Tiled's own rule for
  # its flip flags, applied to the F: across the diagonal first, then
  # horizontally, then vertically. The renderer gets there a different way —
  # quarter turns, then a mirror — so a turn the wrong way fails here.
  describe 'turned tiles, through a real window' do
    # [horizontal, vertical, diagonal] as Tiled flagged each column, and the
    # orientation rgame reads from those flags.
    def painted
      [
        [[false, false, false], [0, false]], [[true, false, false], [0, true]],
        [[false, true, false], [2, true]], [[true, true, false], [2, false]],
        [[false, true, true], [3, false]], [[true, true, true], [3, true]],
        [[false, false, true], [1, true]], [[true, false, true], [1, false]]
      ]
    end

    def f_path = File.expand_path('../../../spec/fixtures/f.png', __dir__)

    # Whether each pixel of the F is dark, as rows of booleans.
    def f_pixels
      frame = RenderedFrame.capture(width: 10, height: 10) do |renderer, app|
        renderer.image_at(RGame::Core::Image.new(app, f_path), 0, 0)
      end
      Array.new(10) { |y| Array.new(10) { |x| frame.at(x, y)[0] < 128 } }
    end

    def tiled_shows(pixels, (horizontal, vertical, diagonal))
      pixels = pixels.transpose if diagonal
      pixels = pixels.map(&:reverse) if horizontal
      pixels = pixels.reverse if vertical
      pixels
    end

    def rgame_draws(column)
      orientations = painted.each_with_index.to_h { |(_flags, orientation), index| [[0, index, 0], orientation] }
      map = StubTileMap.new(width: 8, height: 1, tile_width: 10, tile_height: 10,
                            layers: [Array.new(8, 1)], orientations: orientations)
      frame = RenderedFrame.capture(width: 80, height: 10) do |renderer, app|
        described_class.new(map, [nil, RGame::Core::Image.new(app, f_path)]).draw_layer(renderer, 0, 0, 0, 80, 10)
      end
      Array.new(10) { |y| Array.new(10) { |x| frame.at((column * 10) + x, y)[0] < 128 } }
    end

    8.times do |column|
      it "draws column #{column + 1} as Tiled shows it" do
        expect(rgame_draws(column)).to eq(tiled_shows(f_pixels, painted[column][0]))
      end
    end
  end

  describe 'culling' do
    # 10x10 of 16px tiles, every one animated so every one is drawn
    # individually and therefore visible to these assertions.
    def wide_map
      StubTileMap.new(width: 10, height: 10, layers: [Array.new(100, 1)], animations: { 1 => [[1, 0.1]] })
    end

    # The [col, row] of each animated tile drawn, recovered from its position.
    # Positions are world coordinates, so the cell is a plain division — the
    # cull rect does not move them.
    def drawn_cells(cull_x, cull_y, width, height)
      described_class.new(wide_map, tiles).draw_layer(renderer, 0, cull_x, cull_y, width, height)
      renderer.calls_to(:image_at).map { |call| [call.args[1] / 16, call.args[2] / 16] }
    end

    it 'draws only the tiles the viewport covers' do
      # Cull rect at (32, 32), 32x32: columns 2..3, rows 2..3.
      expect(drawn_cells(32, 32, 32, 32)).to contain_exactly([2, 2], [3, 2], [2, 3], [3, 3])
    end

    it 'includes the tile the camera corner sits on' do
      # Exclusive at the near edge would leave a one-tile gap along the top and
      # left of the screen whenever the camera is not on a tile boundary.
      expect(drawn_cells(32, 32, 32, 32)).to include([2, 2])
    end

    it 'stops before the tile past the far edge' do
      expect(drawn_cells(32, 32, 32, 32)).not_to include([4, 2])
    end

    it 'covers a viewport that does not divide evenly by the tile size' do
      # 40 px of view over 16 px tiles reaches into column 4, and the ceil is
      # what stops a strip of nothing along the right-hand edge.
      expect(drawn_cells(32, 32, 40, 16)).to contain_exactly([2, 2], [3, 2], [4, 2])
    end
  end

  # Everything above asserts on recorded calls, which is the right tier for
  # "which tile, in which band, at which coordinate". What it cannot say is
  # whether a map drawn in world coordinates then lands where the caller's
  # transform puts it — and that is precisely what changed when placement moved
  # out of this class. So one pixel, through a real window.
  describe 'placement, through a real window' do
    # A 2x2 map of 16px tiles, every tile solid white, drawn with no animation
    # so the whole thing goes through the baked recording.
    def white_map
      StubTileMap.new(width: 2, height: 2, layers: [[1, 1, 1, 1]])
    end

    def draw_map_at(dx, dy)
      RenderedFrame.capture(width: 64, height: 64) do |renderer, app|
        image = RGame::Core::Image.new(app, PngFixture.write(16, 16) { [255, 255, 255, 255] })
        map = described_class.new(white_map, [nil, image])
        renderer.translated(dx, dy) { map.draw_layer(renderer, 0, 0, 0, 64, 64) }
      end
    end

    it 'draws at the world origin when the caller applies no transform' do
      expect(draw_map_at(0, 0).about?(4, 4, [255, 255, 255, 255])).to be(true)
    end

    # The camera offset a WorldView applies. The map has to move with it, which
    # is the whole reason its own output carries no offset any more.
    it 'moves with the caller\'s translate' do
      frame = draw_map_at(20, 0)
      expect(frame.about?(4, 4, [26, 26, 38, 255])).to be(true)
      expect(frame.about?(24, 4, [255, 255, 255, 255])).to be(true)
    end

    # One bake, replayed under two different transforms in the same frame —
    # split-screen in miniature, and the property that makes it affordable.
    it 'replays one bake under two transforms in a single frame' do
      frame = RenderedFrame.capture(width: 64, height: 64) do |renderer, app|
        image = RGame::Core::Image.new(app, PngFixture.write(16, 16) { [255, 255, 255, 255] })
        map = described_class.new(white_map, [nil, image])
        renderer.clipped(0, 0, 64, 32) do
          renderer.translated(0, 0) { map.draw_layer(renderer, 0, 0, 0, 64, 64) }
        end
        renderer.clipped(0, 32, 64, 32) do
          renderer.translated(24, 32) { map.draw_layer(renderer, 0, 0, 0, 64, 64) }
        end
      end

      expect(frame.about?(4, 4, [255, 255, 255, 255])).to be(true)
      expect(frame.about?(28, 36, [255, 255, 255, 255])).to be(true)
      expect(frame.about?(4, 36, [26, 26, 38, 255])).to be(true)
    end
  end

  it 'keeps the map it was built from, for the scene to read' do
    # A scene asks it for collision and world bounds, which are the map's
    # business rather than this class's.
    map = two_layer_map

    expect(described_class.new(map, tiles).map).to equal(map)
  end
end
