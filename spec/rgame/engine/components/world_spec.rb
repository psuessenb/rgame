# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::World do
  subject(:world) { described_class.new(width: 640, height: 480) }

  it 'reports the bounds it was built with' do
    expect([world.world_width, world.world_height]).to eq([640, 480])
  end

  it 'answers the WorldBounds contract, so a component can ask for that instead' do
    node = RGame::Engine::Node2D.new
    node.add_component(world)

    expect(node.system(RGame::Engine::Components::WorldBounds)).to be(world)
  end
end
