# frozen_string_literal: true

RSpec.describe RGame::Engine::Pool do
  # A minimal poolable: just a mutable dead flag. Anonymous so it doesn't leak.
  let(:item_class) { Struct.new(:dead) }

  it 'builds a fresh object via the factory when the free list is empty' do
    n = 0
    pool = described_class.new { n += 1 }
    expect(pool.acquire).to eq(1)
    expect(pool.acquire).to eq(2)
    expect(pool.size).to eq(2)
  end

  it 'reuses reclaimed objects instead of building new ones' do
    built = 0
    klass = item_class
    pool = described_class.new do
      built += 1
      klass.new(false)
    end
    a = pool.acquire
    b = pool.acquire
    pool.reclaim_if { |obj| obj.equal?(a) } # a → free list

    c = pool.acquire
    expect(c).to equal(a)       # recycled, not freshly built
    expect(built).to eq(2)      # factory only ran twice
    expect(pool.active).to contain_exactly(b, c)
  end

  it 'reclaim_if removes every dead object in a single pass' do
    klass = item_class
    pool = described_class.new { klass.new(false) }
    items = Array.new(4) { pool.acquire }
    items[0].dead = true
    items[2].dead = true

    pool.reclaim_if(&:dead)
    expect(pool.active).to contain_exactly(items[1], items[3])
    expect(pool.size).to eq(2)
  end

  it 'enumerates only active objects with each' do
    pool = described_class.new { +'x' }
    a = pool.acquire
    b = pool.acquire
    expect { |probe| pool.each(&probe) }.to yield_successive_args(a, b)
  end

  it 'is empty until something is acquired, and again once all are reclaimed' do
    klass = item_class
    pool = described_class.new { klass.new(false) }
    expect(pool).to be_empty

    item = pool.acquire
    expect(pool).not_to be_empty

    item.dead = true
    pool.reclaim_if(&:dead)
    expect(pool).to be_empty
  end
end
