# frozen_string_literal: true

RSpec.describe Engine::Components::ScreenWrap do
  subject(:wrap) { described_class.new(width: 100, height: 80, margin: 5) }

  let(:node) { Engine::Node2D.new }

  before { node.add_component(wrap) }

  describe '#update' do
    it 'wraps a node past the left edge round to the right' do
      node.x = -6
      wrap.update(0.0)
      expect(node.x).to eq(105) # width + margin
    end

    it 'wraps a node past the right edge round to the left' do
      node.x = 106
      wrap.update(0.0)
      expect(node.x).to eq(-5) # -margin
    end

    it 'wraps a node past the top edge round to the bottom' do
      node.y = -6
      wrap.update(0.0)
      expect(node.y).to eq(85) # height + margin
    end

    it 'wraps a node past the bottom edge round to the top' do
      node.y = 86
      wrap.update(0.0)
      expect(node.y).to eq(-5)
    end

    it 'leaves a node inside the bounds untouched' do
      node.x = 50
      node.y = 40
      wrap.update(0.0)
      expect([node.x, node.y]).to eq([50, 40])
    end
  end
end
