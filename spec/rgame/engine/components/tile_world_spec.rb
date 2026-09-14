# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::TileWorld do
  subject(:world) { described_class.new(map: map, tilemap_id: :level, cameras: [camera]) }

  let(:map) { StubTileMap.new(layers: [[1, 2, 0, 3]], tileset: StubTileset.new) }

  # A verified double: the component writes the map's bounds into every camera
  # it is given, and a double catches either setter being renamed.
  let(:camera) do
    instance_double(RGame::Engine::Camera, :world_width= => nil, :world_height= => nil)
  end

  # It is a system, not a drawer — RGame::Engine::TileMapLayer draws the map,
  # inside the world band, so that it is drawn once per viewport like the rest
  # of the world. What is left here is what actors ask about.
  describe 'the animation clock' do
    # Nothing below this reads a wall clock — see CLAUDE.md, "`draw` renders
    # state; time enters through `update`" — so the elapsed seconds animated
    # tiles run on have to come from somewhere. Here, out of `update`.
    it 'starts at zero' do
      expect(world.elapsed).to eq(0.0)
    end

    it 'accumulates dt' do
      3.times { world.update(0.5) }
      expect(world.elapsed).to eq(1.5)
    end

    it 'stands still while nothing updates it' do
      # What pausing looks like from here: a scene that stops ticking stops the
      # water. A wall clock could not express that.
      world.update(0.25)
      expect(world.elapsed).to eq(0.25)
    end
  end

  describe 'bounding the cameras it is given' do
    # A camera may not show past the world's edges, and the map is what knows
    # how big the world is. The cameras themselves belong to players.
    it 'sets each camera\'s world size from the map' do
      world
      expect(camera).to have_received(:world_width=).with(map.pixel_width)
    end

    it 'bounds a camera that arrives later, as a joining player\'s does' do
      later = instance_double(RGame::Engine::Camera, :world_width= => nil, :world_height= => nil)
      world.bound(later)
      expect(later).to have_received(:world_height=).with(map.pixel_height)
    end
  end

  it 'names the tile map it draws, for the layer to look up' do
    expect(world.tilemap_id).to eq(:level)
  end

  describe 'the world it wraps' do
    it 'reports the map bounds in pixels' do
      expect([world.world_width, world.world_height]).to eq([map.pixel_width, map.pixel_height])
    end
  end

  # It no longer resolves a step. What it owns is the grid as a blocker source, and the
  # actor that wants to be stopped by it borrows this and resolves for itself — see
  # Components::CharacterBody, which builds its own Engine::CollisionSystem.
  describe '#blockers' do
    # A map that answers solidity, which the shared StubTileMap has no reason to.
    let(:solid_map) do
      instance_double(RGame::Engine::TileMap, tile_width: 16, tile_height: 16,
                                              pixel_width: 320, pixel_height: 320)
    end
    let(:world) { described_class.new(map: solid_map, tilemap_id: :level) }

    before { allow(solid_map).to receive(:solid_tile?) { |col, _row| col == 8 } }

    it 'is a blocker source over the map’s own solid tiles and tile size' do
      # A 16x16 box at x 108 stepping 10 right would reach 134; column 8 starts at 128,
      # so it lands with its right edge there.
      expect(world.blockers.resolve_x(108.0, 16.0, 16, 16, 10.0)).to eq(112.0)
    end

    it 'is the same source every time, so every body on the map shares one' do
      first = world.blockers
      expect(world.blockers).to be(first)
    end
  end

  # The same solidity #blockers reads, viewed as a graph for planning a route.
  describe '#nav_grid' do
    let(:solid_map) do
      instance_double(RGame::Engine::TileMap, width: 6, height: 4, tile_width: 16, tile_height: 16,
                                              pixel_width: 96, pixel_height: 64)
    end
    let(:world) { described_class.new(map: solid_map, tilemap_id: :level) }

    before { allow(solid_map).to receive(:solid_tile?) { |col, row| col == 2 && row < 3 } }

    it 'agrees with #solid? cell for cell' do
      cells = (0...4).flat_map { |row| (0...6).map { |col| [col, row] } }
      disagreements = cells.select { |col, row| world.nav_grid.walkable?(col, row) == world.solid?(col, row) }
      expect(disagreements).to be_empty
    end

    it 'is sized to the map in cells' do
      expect([world.nav_grid.width, world.nav_grid.height]).to eq([6, 4])
    end

    it 'has cells the size of the map’s tiles, to turn a world position into one' do
      expect([world.tile_width, world.tile_height]).to eq([16, 16])
    end

    it 'is the same grid every time' do
      first = world.nav_grid
      expect(world.nav_grid).to be(first)
    end

    it 'reads each tile once, however often it is asked for' do
      3.times { world.nav_grid }
      expect(solid_map).to have_received(:solid_tile?).exactly(24).times
    end

    it 'routes round the map’s solid tiles' do
      expect(world.nav_grid.find(0, 0, 4, 0)).to include([2, 3])
    end
  end
end
