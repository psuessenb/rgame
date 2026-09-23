# frozen_string_literal: true

RSpec.describe RGame::Engine::UI::Grid do
  let(:grid) { described_class.new(columns: 3, item_width: 60, item_height: 40, spacing: 10) }

  def items(count) = Array.new(count) { RGame::Engine::UI::PanelButton.new(label: 'Item') }

  it 'fills rows left to right, top to bottom, columns to a row' do
    placed = items(5).tap { grid.arrange(it) }
    expect(placed.map { [it.x, it.y] }).to eq([[0, 0], [70, 0], [140, 0], [0, 50], [70, 50]])
  end

  it 'gives every item its size' do
    placed = items(4).tap { grid.arrange(it) }
    expect(placed.map { [it.width, it.height] }.uniq).to eq([[60, 40]])
  end

  it 'spaces them eight pixels apart unless told otherwise' do
    placed = items(4).tap { described_class.new(columns: 3, item_width: 60, item_height: 40).arrange(it) }
    expect([placed[1].x, placed[3].y]).to eq([68, 48])
  end

  it 'answers its columns, and fills along the horizontal axis' do
    expect([grid.columns, grid.axis]).to eq([3, :horizontal])
  end

  it 'is a Stack, so it places with the same arithmetic as a Column and a Row' do
    expect(grid).to be_a(RGame::Engine::UI::Stack)
  end

  # A grid filled down its columns would step the other way round from every
  # other grid, so there is no keyword to ask for one.
  it 'takes no axis' do
    expect { described_class.new(columns: 3, axis: :vertical, item_width: 60, item_height: 40) }
      .to raise_error(ArgumentError, /unknown keyword: :axis/)
  end

  it 'refuses columns that are not a positive Integer' do
    expect { described_class.new(columns: 0, item_width: 60, item_height: 40) }
      .to raise_error(ArgumentError, /columns: must be a positive Integer, not 0/)
  end

  it 'refuses a Float for columns' do
    expect { described_class.new(columns: 2.5, item_width: 60, item_height: 40) }
      .to raise_error(ArgumentError, /2\.5/)
  end

  describe '#bounds' do
    it 'encloses every full row' do
      expect(grid.bounds(items(6))).to eq([0, 0, 200, 90])
    end

    it 'is as wide as a full row when the last row is short' do
      expect(grid.bounds(items(4))).to eq([0, 0, 200, 90])
    end

    it 'is as wide as its buttons when a single row is short' do
      expect(grid.bounds(items(2))).to eq([0, 0, 130, 40])
    end

    it 'has no extent for no items' do
      expect(grid.bounds([])).to eq([0, 0, 0, 0])
    end

    it 'ends where the last full row\'s last item ends' do
      placed = items(6).tap { grid.arrange(it) }
      _, _, width, height = grid.bounds(placed)
      expect([width, height]).to eq([placed.last.x + placed.last.width, placed.last.y + placed.last.height])
    end
  end

  describe 'visible_rows:' do
    let(:window) { described_class.new(columns: 3, item_width: 60, item_height: 40, spacing: 10, visible_rows: 2) }

    it 'answers it' do
      expect([window.visible_rows, grid.visible_rows]).to eq([2, nil])
    end

    it 'places the first row asked for at the origin' do
      placed = items(7).tap { window.arrange(it, 1) }
      expect(placed.map(&:y)).to eq([-50, -50, -50, 0, 0, 0, 50])
    end

    it 'bounds the window, however many rows are filled' do
      expect([window.bounds(items(7)), window.bounds(items(1)), window.bounds([])])
        .to eq([[0, 0, 200, 90]] * 3)
    end

    it 'refuses a count that is not a positive Integer' do
      expect { described_class.new(columns: 3, item_width: 60, item_height: 40, visible_rows: 0) }
        .to raise_error(ArgumentError, /visible_rows:/)
    end
  end
end
