# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::Identity do
  def node_with(id)
    RGame::Engine::Node2D.new.tap { |node| node.add_component(described_class.new(id: id)) }
  end

  describe 'the id it carries' do
    it 'reports what it was given' do
      expect(described_class.new(id: 7).id).to eq(7)
    end

    it 'takes any object a game wants to name things with' do
      # Integers are the usual choice, but nothing here cares — a game keying by
      # Symbol or String is naming its own objects and this does not second-guess
      # it. The one rule is uniqueness, which is the game's to keep.
      expect(described_class.new(id: :dolly).id).to eq(:dolly)
      expect(described_class.new(id: 'ewe-3').id).to eq('ewe-3')
    end

    it 'refuses a nil id' do
      # nil is what an absent id looks like, and `Identity.of` already answers it
      # for a node with no identity. Allowing one here would make the two
      # indistinguishable at the point it matters — a save writing nil where a
      # reference should be.
      expect { described_class.new(id: nil) }.to raise_error(ArgumentError, /needs an id/)
    end
  end

  describe '.of' do
    it 'reads the id off a node' do
      expect(described_class.of(node_with(7))).to eq(7)
    end

    it 'answers nil for a node carrying no identity' do
      # Not every node has one, and asking is how save code finds out. A raise
      # here would make the caller check twice.
      expect(described_class.of(RGame::Engine::Node2D.new)).to be_nil
    end

    it 'answers nil for no node at all' do
      # The case this exists for: a component holding a *node* reference that
      # happens to be nil — an untargeted `Targeting#target` — being written to a
      # save. One call, one answer, no guard at the call site.
      expect(described_class.of(nil)).to be_nil
    end
  end

  describe 'what it is for' do
    it 'turns a node reference into something a save file can hold' do
      # The direction that matters. Something holding a node has only the node to
      # go on, and a node cannot be written to a file.
      flock = Array.new(3) { |i| node_with(i + 1) }
      chased = flock[1]

      expect(described_class.of(chased)).to eq(2)
    end

    it 'survives the collection being rebuilt in a different order' do
      # Why an array index will not do once members can die. The save holds ids;
      # the rebuilt flock is missing one and in another order; the reference
      # still finds the right sheep.
      saved_target = 3
      rebuilt = [node_with(3), node_with(1)] # sheep 2 died, and these came back swapped

      found = rebuilt.find { |sheep| described_class.of(sheep) == saved_target }

      expect(found).to be(rebuilt.first)
    end
  end
end
