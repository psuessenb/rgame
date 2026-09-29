# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::Blink do
  let(:root) { RGame::Engine::Node2D.new }
  let(:node) { RGame::Engine::Node2D.new }
  let(:blink) { node.add_component(described_class.new) }

  def dt = 1.0 / 60

  def opacities(seconds)
    Array.new((seconds / dt).round) do
      node.update(dt)
      node.opacity
    end
  end

  def runs(values) = values.chunk_while { |a, b| a == b }.map { [it.first, it.size] }

  before do
    blink
    root.add_node(node)
    root.enter_tree
  end

  describe '.new' do
    it 'refuses an interval that is not a positive number of seconds' do
      expect { described_class.new(interval: 0) }.to raise_error(ArgumentError, /interval must be a positive/)
      expect { described_class.new(interval: '0.1') }.to raise_error(ArgumentError, /"0.1"/)
    end
  end

  describe '#start' do
    # Six ticks a blink at 60 a second. The first shows for five, since the node
    # already showed on the tick it started, and the last tick of the blink gives
    # the opacity back.
    it 'shows the node for a blink, then hides it for one, until its seconds have passed' do
      blink.start(0.5)

      expect(runs(opacities(0.5))).to eq([[1, 5], [0, 6], [1, 6], [0, 6], [1, 7]])
    end

    it 'blinks at the interval it was given' do
      quick = RGame::Engine::Node2D.new.tap { it.add_component(described_class.new(interval: 0.05)) }
      root.add_node(quick)
      quick.get_component(described_class).start(0.25)
      seen = Array.new(15) do
        quick.update(dt)
        quick.opacity
      end

      expect(runs(seen)).to eq([[1, 2], [0, 3], [1, 3], [0, 3], [1, 4]])
    end

    it 'refuses seconds that are not positive, and a blink under way carries on' do
      blink.start(0.5)
      opacities(0.15)

      expect { blink.start(0) }.to raise_error(ArgumentError, /seconds must be a positive number of seconds, not 0/)
      expect([node.opacity, blink]).to match([0, be_blinking])
    end
  end

  describe 'the opacity it found' do
    before { node.opacity = 0.75 }

    it 'comes back when the blink ends' do
      blink.start(0.5)
      opacities(0.3)
      expect(node.opacity).to eq(0)

      opacities(0.3)
      expect([node.opacity, blink.blinking?]).to eq([0.75, false])
    end

    it 'is the first one when a second start restarts the blink' do
      blink.start(0.5)
      opacities(0.15)
      blink.start(0.5)
      opacities(0.6)

      expect(node.opacity).to eq(0.75)
    end

    it 'comes back at once on stop' do
      blink.start(0.5)
      opacities(0.15)
      blink.stop

      expect([node.opacity, blink.blinking?]).to eq([0.75, false])
    end

    it 'comes back when the node leaves the tree mid-blink' do
      blink.start(0.5)
      opacities(0.15)
      root.remove_node(node)

      expect([node.opacity, blink.blinking?]).to eq([0.75, false])
    end

    it 'comes back when the Blink leaves the node mid-blink' do
      blink.start(0.5)
      opacities(0.15)
      node.remove_component(described_class)

      expect([node.opacity, blink.blinking?]).to eq([0.75, false])
    end
  end

  describe '#stop' do
    it 'changes nothing with no blink under way' do
      node.opacity = 0.5
      blink.stop

      expect([node.opacity, blink.blinking?]).to eq([0.5, false])
    end
  end

  describe '#blinking?' do
    it 'is false until a start, and true from it to the end of the blink' do
      seen = [blink.blinking?]
      blink.start(0.25)
      seen << blink.blinking?
      opacities(0.25 - dt)
      seen << blink.blinking?
      opacities(dt)

      expect(seen << blink.blinking?).to eq([false, true, true, false])
    end
  end

  # Each call is a whole blink, from its start through the shown and hidden
  # spells to the tick that gives the opacity back.
  it 'allocates nothing over a whole blink' do
    expect do
      blink.start(0.5)
      31.times { node.update(dt) }
    end.to allocate_nothing.over(100)
  end
end
