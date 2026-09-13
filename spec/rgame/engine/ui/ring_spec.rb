# frozen_string_literal: true

RSpec.describe RGame::Engine::UI::Ring do
  let(:ring) { described_class.new(radius: 100, item_width: 40, item_height: 20) }

  def items(count) = Array.new(count) { RGame::Engine::UI::PanelButton.new(label: 'Item') }

  def centre(item) = [(item.x + 20).round(6), (item.y + 10).round(6)]

  it 'puts the first item straight up, centred on its point of the circle' do
    placed = items(4).tap { ring.arrange(it) }
    expect(centre(placed.first)).to eq([0, -100])
  end

  it 'goes clockwise, so the second of four is to the right' do
    placed = items(4).tap { ring.arrange(it) }
    expect(centre(placed[1])).to eq([100, 0])
  end

  it 'spaces the items by how many there are' do
    placed = items(5).tap { ring.arrange(it) }
    expect(centre(placed[1]).last).to be_within(0.001).of(-100 * Math.cos(Math::PI * 2 / 5))
  end

  it 'gives every item its size' do
    placed = items(3).tap { ring.arrange(it) }
    expect(placed.map { [it.width, it.height] }.uniq).to eq([[40, 20]])
  end

  describe '#bounds' do
    def contains?(bounds, item)
      left, top, width, height = bounds
      epsilon = 1e-9
      item.x >= left - epsilon && item.y >= top - epsilon &&
        item.x + item.width <= left + width + epsilon && item.y + item.height <= top + height + epsilon
    end

    it 'is the square round the whole circle of slots, centred on the origin' do
      expect(ring.bounds(items(4))).to eq([-120.0, -110.0, 240, 220])
    end

    it 'has no extent for no items' do
      expect(ring.bounds([])).to eq([0, 0, 0, 0])
    end

    # Three, five and eight put slots off the axes, which is what a box of just
    # the radius, without the slot size, gets wrong.
    [1, 2, 3, 5, 8].each do |count|
      it "contains every slot of a ring of #{count}" do
        placed = items(count).tap { ring.arrange(it) }
        bounds = ring.bounds(placed)
        expect(placed).to all(satisfy { contains?(bounds, it) })
      end
    end
  end
end
