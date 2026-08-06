# frozen_string_literal: true

RSpec.describe RGame::Engine::CameraView do
  let(:camera)   { instance_double(RGame::Engine::Camera, x: 30.0, y: 20.0) }
  let(:view)     { described_class.new(camera: camera) }
  let(:child)    { RGame::Engine::Node2D.new }
  let(:renderer) { instance_double(FakeRenderer) }

  before do
    allow(renderer).to receive(:translated).and_yield # apply the view transform, run children
    allow(child).to receive(:draw)
    view.add_node(child)
  end

  describe '#draw' do
    it 'wraps the child subtree in a translate by the negated camera offset' do
      view.draw(renderer)
      expect(renderer).to have_received(:translated).with(-30.0, -20.0)
    end

    it 'still draws the children (the view transform yields to them)' do
      view.draw(renderer)
      expect(child).to have_received(:draw).with(renderer)
    end
  end
end
