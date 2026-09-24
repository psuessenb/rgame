# frozen_string_literal: true

# Where each anchor puts a picture is pinned through the two components that
# draw with it. This file pins what they cannot show: that the arithmetic
# allocates nothing, a picture of no size included.
RSpec.describe RGame::Engine::Anchor do
  it 'measures a 16x32 picture from the origin, for each anchor' do
    edges = described_class::NAMES.map { [described_class.left(it, 16), described_class.top(it, 32)] }

    expect(edges).to eq([[-8, -16], [-8, -32], [0, 0]])
  end

  # -0.0 is a heap Float on this Ruby, so a sizeless node would allocate on
  # every draw.
  it 'answers an Integer 0 for a picture of no size' do
    expect([described_class.left(:center, 0.0), described_class.top(:bottom, 0.0)]).to eq([0, 0])
    expect(described_class.top(:bottom, 0.0)).to be_an(Integer)
  end

  it 'allocates nothing, whole or fractional, sized or not' do
    sizes = [16, 22.5, 0, 0.0]
    described_class::NAMES.each { |anchor| sizes.each { described_class.left(anchor, it) } }

    expect do
      described_class::NAMES.each do |anchor|
        sizes.each do |size|
          described_class.left(anchor, size)
          described_class.top(anchor, size)
        end
      end
    end.to allocate_nothing
  end

  it 'passes a known anchor through and refuses any other' do
    expect(described_class.check!(:bottom)).to eq(:bottom)
    expect { described_class.check!('bottom') }.to raise_error(ArgumentError, /one of \[:center, :bottom, :top_left\]/)
  end
end
