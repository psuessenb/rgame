# frozen_string_literal: true

# A shrink called by hand, as a Fall calls it, and under a Fall of a quarter of
# a second, on a node drawn at twice its size.
RSpec.describe RGame::Engine::Components::Shrink do
  let(:root) { RGame::Engine::Node2D.new }
  let(:world) { root.add_node(RGame::Engine::Node2D.new) }
  let(:node) do
    RGame::Engine::Node2D.new.tap do |node|
      node.scale = 2
      world.add_node(node)
    end
  end
  let(:shrink) { node.add_component(described_class.new) }

  def dt = 1.0 / 60

  def tick
    root.update(dt)
    root.sweep_freed
  end

  describe 'called by hand' do
    before { root.enter_tree }

    it 'scales the node from the scale it found toward 0, eased in' do
      shrink.start
      shown = [0.0, 0.5, 1.0].map { shrink.show(it).then { node.scale } }

      expect(shown).to eq([2.0, 1.5, 0.0])
    end

    it 'gives the scale it found back at finish' do
      shrink.start
      shrink.show(0.5)
      shrink.finish

      expect(node.scale).to eq(2)
    end

    it 'changes nothing at a finish with no start before it' do
      shrink.start
      shrink.finish
      node.scale = 3
      shrink.finish

      expect(node.scale).to eq(3)
    end

    it 'gives the scale back as it leaves its node mid-shrink' do
      shrink.start
      shrink.show(0.5)
      node.remove_component(described_class)

      expect(node.scale).to eq(2)
    end
  end

  describe 'under a Fall' do
    let(:fall) { node.add_component(RGame::Engine::Components::Fall.new(duration: 0.25)) }

    before do
      fall
      shrink
      root.enter_tree
    end

    it 'shrinks the node from 2 toward 0 over the fall, and gives it 2 back at the end' do
      fall.start
      scales = []
      scales << node.scale while tick.then { fall.falling? }

      expect(scales.first).to be_within(1e-9).of(2 * (1 - ((dt / 0.25)**2)))
      expect(scales.each_cons(2).all? { |a, b| b < a }).to be(true)
      expect(node.scale).to eq(2)
    end

    it 'gives the scale back at Fall#finish' do
      fall.start
      5.times { tick }
      fall.finish

      expect(node.scale).to eq(2)
    end

    it 'gives the scale back when the node leaves the tree mid-fall' do
      fall.start
      5.times { tick }
      world.remove_node(node)

      expect(node.scale).to eq(2)
    end
  end
end
