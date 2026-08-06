# frozen_string_literal: true

# Guards the M1 input-allocation hygiene: the mapper reuses one Actions snapshot
# instead of allocating per poll.
RSpec.describe RGame::Engine::ActionMapper do
  let(:map) do
    {
      move_x: { axis: %i[left right] },
      confirm: { button: %i[confirm] }
    }
  end

  let(:backend) do
    Struct.new(:down_ids) do
      def down?(id) = down_ids.include?(id)
      def pointer_x = 0
      def pointer_y = 0
    end.new(%i[right])
  end

  it 'returns the same Actions instance on every poll' do
    mapper = described_class.new(map)
    first = mapper.poll(backend)
    second = mapper.poll(backend)
    expect(second).to equal(first)
  end

  it 'is allocation-free in steady state' do
    mapper = described_class.new(map)
    mapper.poll(backend) # warm up: build hash keys + the Actions object once

    before = GC.stat(:total_allocated_objects)
    1000.times { mapper.poll(backend) }
    after = GC.stat(:total_allocated_objects)

    # The old code allocated an Actions + 2 hashes per poll (~3000 for 1000 polls);
    # reuse should bring that to ~0.
    expect(after - before).to be < 100
  end
end
