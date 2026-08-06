# frozen_string_literal: true

RSpec.describe RGame::Engine::PlayerController do
  it 'maps the move_x/move_y actions to an intent vector' do
    input = RGame::Engine::Actions.new(axes: { move_x: -1.0, move_y: 1.0 })
    expect(described_class.new.intent(0.016, input)).to eq([-1.0, 1.0])
  end

  it 'is neutral when no axes are set' do
    expect(described_class.new.intent(0.016, RGame::Engine::Actions.new)).to eq([0.0, 0.0])
  end
end
