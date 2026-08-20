# frozen_string_literal: true

# The mapper runs once per player per tick, so it must not allocate. It reuses
# one Actions snapshot over three hashes it mutates in place, and the hashes are
# seeded from the map at construction so they are warm before the first poll.
RSpec.describe RGame::Engine::ActionMapper do
  let(:controls) { RGame::Util::Controls }

  let(:map) do
    RGame::Engine::InputMap.new(
      move_x: { axis: [RGame::Util::Controls::KEY_LEFT, RGame::Util::Controls::KEY_RIGHT],
                stick: RGame::Util::Controls::AXIS_LEFT_X },
      fire: { buttons: [RGame::Util::Controls::KEY_SPACE, RGame::Util::Controls::PAD_A] }
    )
  end

  # A pad, so the analog path is exercised too: the dead zone and the
  # digital-vs-analog comparison both run on every poll for move_x.
  let(:pad) { RGame::Util::Controls.gamepad(0) }

  let(:backend) do
    FakeInputBackend.new
                    .hold(RGame::Util::Controls::PAD_A, device: RGame::Util::Controls.gamepad(0))
                    .set_axis(RGame::Util::Controls::AXIS_LEFT_X, 0.6,
                              device: RGame::Util::Controls.gamepad(0))
  end

  it 'returns the same Actions instance on every poll' do
    mapper = described_class.new(map, device: pad)
    expect(mapper.poll(backend)).to equal(mapper.poll(backend))
  end

  it 'is allocation-free in steady state' do
    mapper = described_class.new(map, device: pad)
    mapper.poll(backend) # warm up

    before = GC.stat(:total_allocated_objects)
    1000.times { mapper.poll(backend) }
    after = GC.stat(:total_allocated_objects)

    expect(after - before).to be < 100
  end

  # Passing the device as a keyword on every query is the change this step made,
  # and a keyword that boxed into a Hash would allocate once per id per poll —
  # invisible except as a steady GC drip. Ruby passes keywords on the stack when
  # the callee declares them, and this is what says so out loud.
  it 'does not allocate for the device keyword it passes on every query' do
    mapper = described_class.new(map, device: pad)
    mapper.poll(backend)

    before = GC.stat(:total_allocated_objects)
    100.times { mapper.poll(backend) }
    after = GC.stat(:total_allocated_objects)

    expect(after - before).to be < 10
  end
end
