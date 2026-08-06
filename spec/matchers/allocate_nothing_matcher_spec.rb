# frozen_string_literal: true

# Coverage for the matcher itself: it must pass for an allocation-free block and fail
# for one that allocates every call, so a real per-frame leak can't slip through.
RSpec.describe 'allocate_nothing matcher' do # rubocop:disable RSpec/DescribeClass
  it 'passes for a block that allocates nothing' do
    counter = 0
    expect { counter += 1 }.to allocate_nothing # integer increment: no heap allocation
  end

  it 'fails for a block that allocates on every call' do
    expect { expect { Object.new }.to allocate_nothing.over(200) }
      .to raise_error(RSpec::Expectations::ExpectationNotMetError)
  end

  it 'reports the per-call rate in its failure message' do
    expect { expect { +'a fresh string' }.to allocate_nothing.over(100) }
      .to raise_error(%r{allocated \d+ object\(s\) over 100 calls \(~[\d.]+/call\)})
  end

  it 'supports negation for a block that does allocate' do
    expect { Object.new }.not_to allocate_nothing.over(200)
  end

  it 'absorbs one-time lazy init during warm-up' do
    cache = nil
    # First call builds the cache (allocates); steady-state calls reuse it.
    expect { cache ||= Object.new }.to allocate_nothing.after_warmup(3)
  end

  it 'honours a custom iteration count' do
    counter = 0
    expect { counter += 1 }.to allocate_nothing.over(50)
  end
end
