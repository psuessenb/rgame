# frozen_string_literal: true

# Driven entirely by StubTileMap and FakeRenderer. What a tile map renderer gets
# wrong is which tiles it draws and where — a band mixed up, a tile one column
# off, a bake repeated every frame — and recorded calls state that exactly,
# where a rendered frame would only say the map looks odd.
#
# The map it is handed is checked against the same 'a tile map' contract as the
# real parsed one, in spec/, so a stand-in that had drifted would fail there
# rather than quietly passing here.
RSpec.describe RGame::Core::TileMapRenderer do
  let(:renderer) { FakeRenderer.new }

  # Tile images identifiable by index, so a drawn tile says which one it was.
  let(:tiles) { Array.new(8) { |index| StubImage.new(16, 16, region: [index, 0, 16, 16]) } }

  def tileset(animations: {}) = StubTileset.new(firstgid: 1, animations: animations)

  # 2x2, two layers, the second flagged above. Layer 0 has three tiles, layer 1
  # has one.
  def two_band_map(animations: {})
    StubTileMap.new(layers: [[1, 2, 0, 3], [0, 0, 4, 0]], above: [false, true],
                    tileset: tileset(animations: animations))
  end

  # The local ids baked into the recording the last draw replayed.
  def baked_ids
    recording = renderer.calls_to(:recording_draw).last.args.first
    recording.calls_to(:image_at).map { |call| call.args.first.region.first }
  end

  # The local ids drawn straight into the frame, outside any recording.
  def drawn_ids = renderer.calls_to(:image_at).map { |call| call.args.first.region.first }

  describe 'the two bands' do
    it 'bakes only the below layers into #draw' do
      described_class.new(two_band_map, tiles).draw(renderer, 0, 0, 64, 64)

      # Layer 0's gids 1, 2 and 3 are local 0, 1 and 2. Layer 1's gid 4 is not
      # in this band and must not appear.
      expect(baked_ids).to contain_exactly(0, 1, 2)
    end

    it 'bakes only the above layers into #draw_overlay' do
      described_class.new(two_band_map, tiles).draw_overlay(renderer, 0, 0, 64, 64, z: 20)

      expect(baked_ids).to eq([3])
    end

    it 'skips empty tiles' do
      # gid 0 is "nothing here". Drawing it would put tile 255 — or whatever
      # local_id(0) works out to — across every hole in the map.
      described_class.new(two_band_map, tiles).draw(renderer, 0, 0, 64, 64)

      expect(baked_ids.length).to eq(3)
    end
  end

  describe 'baking' do
    it 'places each tile at its own grid position' do
      described_class.new(two_band_map, tiles).draw(renderer, 0, 0, 64, 64)

      recording = renderer.calls_to(:recording_draw).last.args.first
      expect(recording.calls_to(:image_at).map { |call| call.args[1..] })
        .to eq([[0, 0], [16, 0], [16, 16]])
    end

    it 'bakes once and replays thereafter' do
      # The bug this class exists to avoid: rebaking every frame turns one call
      # per texture back into one per tile, and nothing shows it but the frame
      # rate.
      map = described_class.new(two_band_map, tiles)
      3.times { map.draw(renderer, 0, 0, 64, 64) }

      replays = renderer.calls_to(:recording_draw)
      expect(replays.length).to eq(3)
      # The same recording all three times. Counting replays alone would not
      # say it: a rebake replays too, it just throws the last one away.
      expect(replays.map { |call| call.args.first }.uniq.length).to eq(1)
    end

    it 'keeps the two bands baked separately' do
      map = described_class.new(two_band_map, tiles)
      map.draw(renderer, 0, 0, 64, 64)
      below = renderer.calls_to(:recording_draw).last.args.first
      map.draw_overlay(renderer, 0, 0, 64, 64, z: 20)
      above = renderer.calls_to(:recording_draw).last.args.first

      expect(above).not_to equal(below)
    end

    # The map draws where its tiles live and the caller's transform puts them on
    # screen, so the replay carries no offset at all — which is what makes one
    # bake serve every viewport rather than only the camera it was baked for.
    it 'replays the layer at its own origin, whatever the cull rect' do
      described_class.new(two_band_map, tiles).draw(renderer, 48, 32, 64, 64)

      expect(renderer.calls_to(:recording_draw).last.args[1..]).to eq([0, 0])
    end

    it 'replays the overlay at the z it was given' do
      described_class.new(two_band_map, tiles).draw_overlay(renderer, 0, 0, 64, 64, z: 20)

      expect(renderer.calls_to(:recording_draw).last.options[:z]).to eq(20)
    end
  end

  describe 'animated tiles' do
    let(:animations) { { 0 => [[0, 100], [1, 100]] } }

    it 'leaves them out of the bake' do
      described_class.new(two_band_map(animations: animations), tiles).draw(renderer, 0, 0, 64, 64)

      # Local 0 is animated; 1 and 2 are not.
      expect(baked_ids).to contain_exactly(1, 2)
    end

    it 'draws them into the frame instead, at their world position' do
      described_class.new(two_band_map(animations: animations), tiles).draw(renderer, 0, 0, 64, 64)

      expect(renderer.calls_to(:image_at).map { |call| call.args[1..] }).to eq([[0, 0]])
    end

    it 'follows elapsed rather than a clock' do
      # Two 100 ms frames. Elapsed is in seconds, and a spec picks the frame it
      # wants instead of stubbing time.
      map = described_class.new(two_band_map(animations: animations), tiles)

      map.draw(renderer, 0, 0, 64, 64, elapsed: 0.0)
      map.draw(renderer, 0, 0, 64, 64, elapsed: 0.15)
      map.draw(renderer, 0, 0, 64, 64, elapsed: 0.25)

      expect(drawn_ids).to eq([0, 1, 0])
    end

    it 'stands still when elapsed does not move' do
      # What pausing looks like from here: the same number in, the same frame
      # out, however many times it is drawn.
      map = described_class.new(two_band_map(animations: animations), tiles)
      3.times { map.draw(renderer, 0, 0, 64, 64, elapsed: 0.15) }

      expect(drawn_ids).to eq([1, 1, 1])
    end

    it 'draws them in world coordinates, like the baked layer' do
      described_class.new(two_band_map(animations: animations), tiles)
                     .draw(renderer, 8, 4, 64, 64)

      # Column 0, row 0 of a 16px tileset: at the origin, not at -cull.
      expect(renderer.calls_to(:image_at).map { |call| call.args[1..] }).to eq([[0, 0]])
    end

    it 'draws the overlay band at the overlay z' do
      map = StubTileMap.new(layers: [[0, 0, 0, 0], [1, 0, 0, 0]], above: [false, true],
                            tileset: tileset(animations: animations))
      described_class.new(map, tiles).draw_overlay(renderer, 0, 0, 64, 64, z: 20)

      expect(renderer.calls_to(:image_at).first.options[:z]).to eq(20)
    end
  end

  describe 'culling' do
    # 10x10 of 16px tiles, every one animated so every one is drawn
    # individually and therefore visible to these assertions.
    def wide_map
      StubTileMap.new(width: 10, height: 10, layers: [Array.new(100, 1)],
                      tileset: tileset(animations: { 0 => [[0, 100]] }))
    end

    # The [col, row] of each animated tile drawn, recovered from its position.
    # Positions are world coordinates, so the cell is a plain division — the
    # cull rect does not move them.
    def drawn_cells(cull_x, cull_y, width, height)
      described_class.new(wide_map, tiles).draw(renderer, cull_x, cull_y, width, height)
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
      StubTileMap.new(width: 2, height: 2, layers: [[1, 1, 1, 1]],
                      tileset: StubTileset.new(firstgid: 1))
    end

    def draw_map_at(dx, dy)
      RenderedFrame.capture(width: 64, height: 64) do |renderer, app|
        image = RGame::Core::Image.new(app, PngFixture.write(16, 16) { [255, 255, 255, 255] })
        map = described_class.new(white_map, Array.new(4) { image })
        renderer.translated(dx, dy) { map.draw(renderer, 0, 0, 64, 64) }
      end
    end

    it 'draws at the world origin when the caller applies no transform' do
      expect(draw_map_at(0, 0).at(4, 4)).to eq([255, 255, 255, 255])
    end

    # The camera offset a WorldView applies. The map has to move with it, which
    # is the whole reason its own output carries no offset any more.
    it 'moves with the caller\'s translate' do
      frame = draw_map_at(20, 0)
      expect([frame.at(4, 4), frame.at(24, 4)])
        .to eq([[26, 26, 38, 255], [255, 255, 255, 255]])
    end

    # One bake, replayed under two different transforms in the same frame —
    # split-screen in miniature, and the property that makes it affordable.
    it 'replays one bake under two transforms in a single frame' do
      frame = RenderedFrame.capture(width: 64, height: 64) do |renderer, app|
        image = RGame::Core::Image.new(app, PngFixture.write(16, 16) { [255, 255, 255, 255] })
        map = described_class.new(white_map, Array.new(4) { image })
        renderer.clipped(0, 0, 64, 32) { renderer.translated(0, 0) { map.draw(renderer, 0, 0, 64, 64) } }
        renderer.clipped(0, 32, 64, 32) { renderer.translated(24, 32) { map.draw(renderer, 0, 0, 64, 64) } }
      end

      expect([frame.at(4, 4), frame.at(28, 36), frame.at(4, 36)])
        .to eq([[255, 255, 255, 255], [255, 255, 255, 255], [26, 26, 38, 255]])
    end
  end

  it 'keeps the map it was built from, for the scene to read' do
    # A scene asks it for collision and world bounds, which are the map's
    # business rather than this class's.
    map = two_band_map

    expect(described_class.new(map, tiles).map).to equal(map)
  end
end
