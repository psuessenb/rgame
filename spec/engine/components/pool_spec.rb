# frozen_string_literal: true

# A minimal pooled node: records whether its reset block ran while it was outside the
# tree, and counts how many times the factory built a fresh one.
class SpecPooledNode < Engine::Node2D
  class << self
    attr_accessor :builds
  end
  self.builds = 0

  attr_reader :reset_in_tree

  def initialize
    super
    self.class.builds += 1
  end

  def reset
    @reset_in_tree = in_tree?
    self
  end
end

RSpec.describe Engine::Components::Pool do
  subject(:pool) { described_class.new { SpecPooledNode.new } }

  let(:owner) { Engine::Node2D.new }

  before do
    SpecPooledNode.builds = 0
    owner.add_component(pool)
    owner.enter_tree
  end

  describe '#spawn' do
    it 'adds the spawned node as a child of the owner and returns it' do
      child = pool.spawn
      expect(owner.children).to eq([child])
    end

    it 'runs the reset block before the node enters the tree' do
      child = pool.spawn(&:reset)
      expect(child.reset_in_tree).to be(false)
      expect(child).to be_in_tree # but it is live afterwards
    end
  end

  describe 'reclaiming on update' do
    it 'detaches a freed node and returns it to the pool to be recycled' do
      first = pool.spawn
      first.queue_free
      pool.update(0.016) # reclaim: detach + back to the free list

      expect(owner.children).to eq([])
      expect(pool.spawn).to be(first) # recycled, not rebuilt
      expect(SpecPooledNode.builds).to eq(1)
    end

    it 'leaves live nodes attached' do
      live = pool.spawn
      pool.update(0.016)
      expect(owner.children).to eq([live])
    end
  end

  describe '#size' do
    it 'counts the active (acquired, not yet reclaimed) nodes' do
      pool.spawn
      pool.spawn
      expect(pool.size).to eq(2)
    end
  end

  describe '#empty?' do
    it 'is true with nothing spawned and again once every node is reclaimed' do
      expect(pool).to be_empty

      child = pool.spawn
      expect(pool).not_to be_empty

      child.queue_free
      pool.update(0.016)
      expect(pool).to be_empty
    end
  end
end
