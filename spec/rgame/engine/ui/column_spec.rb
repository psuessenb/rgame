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

  describe '#bounds' do
    let(:column) { described_class.new(item_width: 200, item_height: 40, spacing: 10) }

    it 'encloses the stacked items, with a gap between each pair and none outside' do
      expect(column.bounds(items(3))).to eq([0, 0, 200, 140])
    end

    it 'is the one slot for a single item' do
      expect(column.bounds(items(1))).to eq([0, 0, 200, 40])
    end

    it 'has no extent for no items' do
      expect(column.bounds([])).to eq([0, 0, 0, 0])
    end

    it 'ends where the last arranged item ends' do
      placed = items(4).tap { column.arrange(it) }
      _, _, width, height = column.bounds(placed)
      expect([width, height]).to eq([placed.last.x + placed.last.width, placed.last.y + placed.last.height])
    end
  end

  describe 'visible_rows:' do
    let(:window) { described_class.new(item_width: 200, item_height: 40, spacing: 10, visible_rows: 2) }

    it 'places the first row asked for at the origin' do
      placed = items(4).tap { window.arrange(it, 2) }
      expect(placed.map(&:y)).to eq([-100, -50, 0, 50])
    end

    it 'bounds the window, however many rows are filled' do
      expect([window.bounds(items(4)), window.bounds([])]).to eq([[0, 0, 200, 90]] * 2)
    end
  end
end
