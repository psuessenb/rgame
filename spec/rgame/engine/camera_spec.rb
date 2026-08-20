# frozen_string_literal: true

RSpec.describe RGame::Engine::Camera do
  subject(:camera) { described_class.new(world_width: 500, world_height: 500) }

  # center_on records intent; resolve turns it into an offset for a viewport of
  # a given size. They are separate because the same camera is drawn through as
  # many viewports as there are players, and clamping depends on which.
  describe '#resolve' do
    it 'centres on the target away from edges' do
      camera.center_on(250, 250).then { camera.resolve(100, 100) }
      expect([camera.x, camera.y]).to eq([200.0, 200.0]) # 250 - 100/2
    end

    it 'clamps to the top-left edge' do
      camera.center_on(10, 10)
      camera.resolve(100, 100)
      expect([camera.x, camera.y]).to eq([0.0, 0.0])
    end

    it 'clamps to the bottom-right edge' do
      camera.center_on(490, 490)
      camera.resolve(100, 100)
      expect([camera.x, camera.y]).to eq([400.0, 400.0]) # world 500 - view 100
    end

    it 'pins to the origin when the world is smaller than the view' do
      small = described_class.new(world_width: 60, world_height: 60)
      small.center_on(30, 30)
      small.resolve(100, 100)
      expect([small.x, small.y]).to eq([0.0, 0.0])
    end

    it 'returns self, so resolving and reading can be chained' do
      expect(camera.resolve(100, 100)).to equal(camera)
    end
  end

  # The reason the viewport size is an argument at all. Near a world edge the
  # clamp is what decides where the target lands on screen, so the same camera
  # frames its target differently in a half-width viewport than a full-width
  # one — which is exactly the case split-screen creates.
  describe 'the same camera through two different viewports' do
    before { camera.center_on(490, 250) }

    it 'clamps harder in the wider view' do
      wide = camera.resolve(400, 100).x
      narrow = camera.resolve(100, 100).x
      expect([wide, narrow]).to eq([100.0, 400.0])
    end

    it 'puts the target at a different place across each view' do
      across_wide = (490 - camera.resolve(400, 100).x) / 400.0
      across_narrow = (490 - camera.resolve(100, 100).x) / 100.0
      expect(across_wide).not_to be_within(0.01).of(across_narrow)
    end
  end

  describe 'an unbounded camera' do
    subject(:camera) { described_class.new }

    # The default, and deliberately "follow exactly" rather than "pin to the
    # origin": a game that has not declared its world yet gets a camera that
    # visibly works instead of one mysteriously stuck.
    it 'follows its target with no clamping at all' do
      camera.center_on(-1000, 5000)
      camera.resolve(100, 100)
      expect([camera.x, camera.y]).to eq([-1050.0, 4950.0])
    end

    it 'starts clamping once a scene gives it bounds' do
      camera.world_width = 500
      camera.world_height = 500
      camera.center_on(10_000, 10_000)
      camera.resolve(100, 100)
      expect([camera.x, camera.y]).to eq([400.0, 400.0])
    end
  end

  describe '#center_on' do
    it 'records the target without resolving anything' do
      camera.center_on(250, 250)
      expect([camera.target_x, camera.target_y]).to eq([250, 250])
    end

    it 'leaves the offset alone until resolve is called' do
      camera.center_on(250, 250)
      expect([camera.x, camera.y]).to eq([0.0, 0.0])
    end
  end
end
