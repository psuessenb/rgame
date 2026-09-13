# frozen_string_literal: true

RSpec.describe RGame::Engine::UI::Stack do
  it 'refuses an axis it does not know' do
    expect { described_class.new(axis: :diagonal, item_width: 60, item_height: 40) }
      .to raise_error(ArgumentError, /:vertical, :horizontal/)
  end

  it 'answers the axis it was built with' do
    expect(described_class.new(axis: :horizontal, item_width: 60, item_height: 40).axis).to eq(:horizontal)
  end

  # Every layout a menu can be built with names the direction Stepping moves
  # along, so a navigation reading it cannot meet one that has none.
  it 'is answered by every shipped layout' do
    layouts = [RGame::Engine::UI::Column.new(item_width: 1, item_height: 1),
               RGame::Engine::UI::Row.new(item_width: 1, item_height: 1),
               RGame::Engine::UI::Ring.new(radius: 1, item_width: 1, item_height: 1)]
    expect(layouts.map(&:axis)).to eq(%i[vertical horizontal vertical])
  end
end
