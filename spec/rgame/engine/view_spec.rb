# frozen_string_literal: true

RSpec.describe RGame::Engine::View do
  let(:camera) { RGame::Engine::Camera.new.center_on(500, 400).resolve(200, 100) }

  describe 'a screen-space view' do
    subject(:view) { described_class.new(x: 0, y: 240, width: 640, height: 240) }

    it 'has no camera' do
      expect(view.camera).to be_nil
    end

    # Its nodes draw relative to its own corner, so its contents start at zero.
    it 'starts at the origin' do
      expect([view.origin_x, view.origin_y]).to eq([0, 0])
    end

    it 'offsets by its own position, so content at zero lands at its corner' do
      expect([view.offset_x, view.offset_y]).to eq([0, 240])
    end
  end

  describe 'a world view' do
    subject(:view) { described_class.new(x: 0, y: 240, width: 200, height: 100, camera: camera) }

    it 'starts where its camera is looking' do
      expect([view.origin_x, view.origin_y]).to eq([camera.x, camera.y])
    end

    # The whole of split-screen in two numbers: shift the world back by the
    # camera, then forward to this viewport's corner on screen.
    it 'offsets by its corner minus its camera' do
      expect([view.offset_x, view.offset_y]).to eq([0 - camera.x, 240 - camera.y])
    end
  end

  describe '#visible?' do
    subject(:view) { described_class.new(width: 100, height: 100, camera: camera) }

    # Coordinates are in the space the caller draws in — world coordinates under
    # a camera — which is the same space origin_x is in.
    it 'sees something at the camera' do
      expect(view.visible?(camera.x, camera.y, 10, 10)).to be(true)
    end

    it 'does not see something off to the left' do
      expect(view.visible?(camera.x - 50, camera.y, 10, 10)).to be(false)
    end

    it 'does not see something off the bottom' do
      expect(view.visible?(camera.x, camera.y + 200, 10, 10)).to be(false)
    end

    it 'sees something straddling an edge' do
      expect(view.visible?(camera.x - 5, camera.y, 10, 10)).to be(true)
    end

    it 'does not see something exactly abutting the left edge' do
      expect(view.visible?(camera.x - 10, camera.y, 10, 10)).to be(false)
    end

    it 'sees something larger than the whole view' do
      expect(view.visible?(camera.x - 500, camera.y - 500, 5000, 5000)).to be(true)
    end

    # Culling runs per drawable per viewport, which with four players is four
    # times as often as it ever was.
    it 'costs no allocation' do
      expect { view.visible?(0, 0, 10, 10) }.to allocate_nothing
    end
  end

  describe 'being reused' do
    # Viewports mutates one of these per viewport rather than building fresh
    # ones, so a node holding on to the object it was handed would be reading
    # last frame's rect with this frame's numbers in it.
    it 'takes new numbers in place' do
      view = described_class.new(width: 10, height: 10)
      view.set(5, 6, 100, 200, camera: camera)
      expect([view.x, view.y, view.width, view.height, view.camera])
        .to eq([5, 6, 100, 200, camera])
    end
  end
end
