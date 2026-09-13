# frozen_string_literal: true

RSpec.describe RGame::Engine::UI::Row do
  def items(count) = Array.new(count) { RGame::Engine::UI::PanelButton.new(label: 'Item') }

  it 'lines items up rightwards from the origin, spacing apart' do
    placed = items(3).tap { described_class.new(item_width: 60, item_height: 40, spacing: 10).arrange(it) }
    expect(placed.map { [it.x, it.y] }).to eq([[0, 0], [70, 0], [140, 0]])
  end

  it 'spaces them eight pixels apart unless told otherwise' do
    placed = items(2).tap { described_class.new(item_width: 60, item_height: 40).arrange(it) }
    expect(placed.last.x).to eq(68)
  end

  it 'gives every item its size' do
    placed = items(2).tap { described_class.new(item_width: 60, item_height: 40).arrange(it) }
    expect(placed.map { [it.width, it.height] }.uniq).to eq([[60, 40]])
  end

  it 'is horizontal' do
    expect(described_class.new(item_width: 60, item_height: 40).axis).to eq(:horizontal)
  end

  # Spelled-out keywords rather than a forwarded `**`, so a row cannot be told
  # to be a column and quietly ignore it.
  it 'takes no axis' do
    expect { described_class.new(axis: :vertical, item_width: 60, item_height: 40) }
      .to raise_error(ArgumentError, /unknown keyword: :axis/)
  end

  describe '#bounds' do
    let(:row) { described_class.new(item_width: 60, item_height: 40, spacing: 10) }

    it 'encloses the lined-up items, with a gap between each pair and none outside' do
      expect(row.bounds(items(3))).to eq([0, 0, 200, 40])
    end

    it 'is the one slot for a single item' do
      expect(row.bounds(items(1))).to eq([0, 0, 60, 40])
    end

    it 'has no extent for no items' do
      expect(row.bounds([])).to eq([0, 0, 0, 0])
    end

    it 'ends where the last arranged item ends' do
      placed = items(4).tap { row.arrange(it) }
      _, _, width, height = row.bounds(placed)
      expect([width, height]).to eq([placed.last.x + placed.last.width, placed.last.y + placed.last.height])
    end

    it 'is a column\'s bounds mirrored' do
      column = RGame::Engine::UI::Column.new(item_width: 40, item_height: 60, spacing: 10)
      _, _, width, height = column.bounds(items(3))
      expect(row.bounds(items(3))).to eq([0, 0, height, width])
    end
  end
end
