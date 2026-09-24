# frozen_string_literal: true

require_relative '../../../tools/drive_test_project'

RSpec.describe DriveTestProject::AllocationProbe do
  let(:warmup) { described_class::WARMUP }

  after { GC.enable }

  # Ticks 1 to the last, counted the way the harness counts them, with
  # `work` run on each tick past the warm-up. The count runs from the warm-up's
  # last tick to the run's, so 120 ticks past the warm-up measure 121.
  def drive(probe, ticks: warmup + 120, &work)
    (1..ticks).each do |number|
      probe.tick(number)
      work&.call(number) if number > warmup
    end
    probe.finish
    probe
  end

  it 'passes a run that allocates nothing once warm' do
    expect(drive(described_class.new)).not_to be_failed
  end

  # Allowing the few objects Ruby's method caches take on the probe's own first
  # calls once it is counting, whichever example runs first.
  it 'leaves the warm-up out of the count' do
    probe = described_class.new
    (1..(warmup + 60)).each do |number|
      probe.tick(number)
      Array.new(1_000) { Object.new } if number < warmup
    end
    probe.finish

    expect(probe.lines.first).to match(/\A\d objects over 61 ticks/)
  end

  # One object a tick is 60 a second: at the default budget, but on every tick.
  it 'fails a run that allocates on every tick, however little' do
    probe = drive(described_class.new) { Object.new }

    expect(probe).to be_failed
    expect(probe.lines[1]).to match(/\A12[01] of 121 ticks allocated anything/)
  end

  it 'fails a run that allocates more a second than its budget, however seldom' do
    probe = drive(described_class.new) { |number| Array.new(500) { Object.new } if number == warmup + 60 }

    expect(probe).to be_failed
    expect(probe.lines.first).to match(/\A50\d objects over 121 ticks: 24\d\.\d a second \(budget 60\)/)
  end

  it 'passes the same run with a budget that allows it' do
    probe = drive(described_class.new(objects_per_second: 300)) do |number|
      Array.new(500) { Object.new } if number == warmup + 60
    end

    expect(probe).not_to be_failed
  end

  it 'names the line that allocated, when a run fails' do
    probe = drive(described_class.new) { Object.new }

    expect(probe.lines.join("\n")).to match(%r{OBJECT spec/tools/drive_test_project/allocation_probe_spec\.rb:\d+})
  end

  it 'reports the worst second' do
    probe = drive(described_class.new(objects_per_second: 1_000)) do |number|
      Array.new(99) { Object.new } if number == warmup + 90
    end

    expect(probe.lines).to include(match(/worst second: 10\d/))
  end

  # A run that measured nothing proved nothing.
  it 'fails a run that ended before its warm-up did' do
    probe = drive(described_class.new, ticks: warmup - 1)

    expect(probe).to be_failed
    expect(probe.lines.first).to include('ended before its 120-tick warm-up')
  end

  it 'turns the collector back on when the run ends' do
    drive(described_class.new)

    expect(GC.enable).to be(false)
  end

  describe 'a script' do
    it 'keeps the defaults when it declares no budget' do
      expect(DriveTestProject::Script.new.budget).to eq({})
    end

    it 'hands on only the limits it declares' do
      script = DriveTestProject::Script.new.allocation_budget(objects_per_second: 800)

      expect(script.budget).to eq(objects_per_second: 800)
    end
  end
end
