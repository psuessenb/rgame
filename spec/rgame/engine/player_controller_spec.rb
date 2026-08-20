# frozen_string_literal: true

RSpec.describe RGame::Engine::PlayerController do
  # Both axes, always: Actions answers only for the actions it was declared
  # with, so a snapshot missing one is a snapshot this controller cannot read.
  def actions(**axes)
    RGame::Engine::Actions.new(axes: { move_x: 0.0, move_y: 0.0 }.merge(axes))
  end

  it 'maps the move_x/move_y actions to an intent vector' do
    expect(described_class.new.intent(0.016, actions(move_x: -1.0, move_y: 1.0))).to eq([-1.0, 1.0])
  end

  it 'is neutral when no axes are set' do
    expect(described_class.new.intent(0.016, actions)).to eq([0.0, 0.0])
  end

  it 'refuses a snapshot that never declared the axes it reads' do
    bare = RGame::Engine::Actions.new
    expect { described_class.new.intent(0.016, bare) }.to raise_error(KeyError, /move_x/)
  end
end
