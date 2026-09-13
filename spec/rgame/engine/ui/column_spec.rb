# frozen_string_literal: true

RSpec.describe RGame::Engine::UI::Column do
  def items(count) = Array.new(count) { RGame::Engine::UI::PanelButton.new(label: 'Item') }

  it 'stacks items downwards from the origin, spacing apart' do
    placed = items(3).tap { described_class.new(item_width: 200, item_height: 40, spacing: 10).arrange(it) }
    expect(placed.map { [it.x, it.y] }).to eq([[0, 0], [0, 50], [0, 100]])
  end

  it 'spaces them eight pixels apart unless told otherwise' do
    placed = items(2).tap { described_class.new(item_width: 200, item_height: 40).arrange(it) }
    expect(placed.last.y).to eq(48)
  end

  it 'gives every item its size' do
    placed = items(2).tap { described_class.new(item_width: 200, item_height: 40).arrange(it) }
    expect(placed.map { [it.width, it.height] }.uniq).to eq([[200, 40]])
  end
end
