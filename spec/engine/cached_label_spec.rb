# frozen_string_literal: true

RSpec.describe Engine::CachedLabel do
  it 'builds the string for a value through the block' do
    label = described_class.new { |score| "Score: #{score}" }
    expect(label[7]).to eq('Score: 7')
  end

  it 'returns the very same String object while the value is unchanged' do
    label = described_class.new { |score| "Score: #{score}" }
    first = label[7]
    expect(label[7]).to equal(first) # same object: no per-frame allocation
  end

  it 'rebuilds when the value changes' do
    label = described_class.new { |score| "Score: #{score}" }
    expect([label[1], label[2]]).to eq(['Score: 1', 'Score: 2'])
  end

  it 'calls the format block only when the value changes' do
    calls = 0
    label = described_class.new do |score|
      calls += 1
      "Score: #{score}"
    end

    label[1]
    label[1]
    label[2]

    expect(calls).to eq(2)
  end

  it 'is allocation-free when reading an unchanged value' do
    label = described_class.new { |score| "Score: #{score}" }
    label[7] # warm up

    before = GC.stat(:total_allocated_objects)
    1000.times { label[7] }
    after = GC.stat(:total_allocated_objects)

    expect(after - before).to be < 100
  end

  it 'requires a format block' do
    expect { described_class.new }.to raise_error(ArgumentError)
  end
end
