# frozen_string_literal: true

RSpec.describe RGame::Engine::TileMapLayer do
  let(:world) do
    RGame::Engine::Components::TileWorld.new(
      map: StubTileMap.new(layers: [[1, 2, 0, 3]], tileset: StubTileset.new), tilemap_id: :level
    )
  end
  let(:camera) { RGame::Engine::Camera.new.center_on(500, 400) }
  let(:renderer) { instance_double(FakeRenderer, tilemap: nil, tilemap_overlay: nil) }

  # The layer belongs inside a WorldView, whose scene carries the TileWorld
  # system it reads its map and clock from.
  let(:scene) { RGame::Engine::Node2D.new.tap { |node| node.add_component(world) } }

  def layer = @layer ||= scene.add_node(described_class.new).tap { scene.enter_tree }

  def view(width: 320, height: 240) = screen_view(width: width, height: height, camera: camera)

  # Driven from the scene, the way the traversal does: a node resolves its
  # origin from its parent's, so the parent has to have been resolved first.
  def draw_frame(into = view)
    layer # mount it
    scene.draw(renderer, into)
  end

  describe 'drawing both bands' do
    # Two calls rather than one because the actors are drawn between them;
    # collapsing them would put every canopy behind every character.
    it 'draws the below band and then the overlay' do
      draw_frame

      expect(renderer).to have_received(:tilemap).ordered
      expect(renderer).to have_received(:tilemap_overlay).ordered
    end

    it 'puts the overlay at the band z the actors are drawn under' do
      draw_frame

      expect(renderer).to have_received(:tilemap_overlay)
        .with(any_args, hash_including(z: RGame::Engine::Components::TileWorld::OVERLAY_Z))
    end

    it 'names the map the scene\'s TileWorld holds' do
      draw_frame

      expect(renderer).to have_received(:tilemap).with(:level, any_args)
    end
  end

  describe 'the cull rect' do
    # It passes the camera through as the region worth drawing, and does no
    # arithmetic of its own — the map draws in world coordinates and the
    # WorldView's translate is what puts it on screen. That is exactly what
    # lets the same map serve every viewport.
    it 'is the camera\'s position and the view\'s size' do
      camera.resolve(320, 240)
      draw_frame

      expect(renderer).to have_received(:tilemap)
        .with(:level, camera.x, camera.y, 320, 240, any_args)
    end

    it 'follows the view, so two viewports cull differently' do
      other = RGame::Engine::Camera.new.center_on(2000, 2000).resolve(100, 100)
      draw_frame(screen_view(width: 100, height: 100, camera: other))

      expect(renderer).to have_received(:tilemap)
        .with(:level, other.x, other.y, 100, 100, any_args)
    end
  end

  describe 'the animation clock' do
    it 'hands the scene\'s elapsed seconds to both bands' do
      3.times { world.update(0.5) }
      draw_frame

      expect(renderer).to have_received(:tilemap).with(any_args, hash_including(elapsed: 1.5))
      expect(renderer).to have_received(:tilemap_overlay)
        .with(any_args, hash_including(elapsed: 1.5))
    end
  end

  # A screen-space band has no camera and so nothing to cull against. That is a
  # misplaced layer rather than a state to cope with, and saying so beats
  # drawing the map at the origin of every HUD.
  it 'refuses to draw outside a world view' do
    expect { draw_frame(screen_view) }
      .to raise_error(/must be inside a WorldView/)
  end
end
