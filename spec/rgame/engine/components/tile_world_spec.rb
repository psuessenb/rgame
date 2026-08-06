# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::TileWorld do
  subject(:world) { described_class.new(map: map, tilemap_id: :level, camera: camera) }

  let(:map) { StubTileMap.new(layers: [[1, 2, 0, 3]], tileset: StubTileset.new) }
  let(:camera) { Struct.new(:x, :y, :viewport_width, :viewport_height).new(8, 16, 320, 240) }

  # Verified against FakeRenderer, which is itself run against the renderer
  # contract — so `elapsed:` being accepted here is not this spec's opinion, it
  # is the interface the live renderer implements.
  let(:renderer) { instance_double(FakeRenderer) }

  before do
    allow(renderer).to receive(:tilemap)
    allow(renderer).to receive(:tilemap_overlay)
  end

  describe 'drawing' do
    it 'draws both bands, leaving room for the actors between them' do
      # Two calls rather than one because the scene draws its actors in between;
      # collapsing them would put every canopy behind every character.
      world.draw(renderer)

      expect(renderer).to have_received(:tilemap).ordered
      expect(renderer).to have_received(:tilemap_overlay)
        .with(any_args, hash_including(z: described_class::OVERLAY_Z)).ordered
    end

    it 'draws through the camera' do
      world.draw(renderer)

      expect(renderer).to have_received(:tilemap).with(:level, 8, 16, 320, 240, any_args)
    end
  end

  describe 'the animation clock' do
    # Nothing below this reads a wall clock — see CLAUDE.md, "`draw` renders
    # state; time enters through `update`" — so the elapsed seconds animated
    # tiles run on have to come from somewhere. Here, out of `update`.
    it 'starts at zero' do
      world.draw(renderer)

      expect(renderer).to have_received(:tilemap).with(any_args, hash_including(elapsed: 0.0))
    end

    it 'accumulates dt and hands the same clock to both bands' do
      3.times { world.update(0.5) }
      world.draw(renderer)

      expect(renderer).to have_received(:tilemap).with(any_args, hash_including(elapsed: 1.5))
      expect(renderer).to have_received(:tilemap_overlay)
        .with(any_args, hash_including(elapsed: 1.5))
    end

    it 'stands still while nothing updates it' do
      # What pausing looks like from here: a scene that stops ticking stops the
      # water. A wall clock could not express that.
      world.update(0.25)
      3.times { world.draw(renderer) }

      expect(renderer).to have_received(:tilemap)
        .with(any_args, hash_including(elapsed: 0.25)).exactly(3).times
    end
  end

  describe 'the world it wraps' do
    it 'reports the map bounds in pixels' do
      expect([world.world_width, world.world_height]).to eq([map.pixel_width, map.pixel_height])
    end
  end
end
