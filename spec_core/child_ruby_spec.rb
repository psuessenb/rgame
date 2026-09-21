# frozen_string_literal: true

RSpec.describe ChildRuby do
  it 'returns what the child printed, and its status' do
    output, errors, status = described_class.capture('puts ARGV.first; warn "careful"', 'hello')

    expect([output, errors, status.success?]).to eq(["hello\n", "careful\n", true])
  end

  it 'loads this checkout' do
    output, = described_class.capture("require 'rgame/version'; puts $LOADED_FEATURES.grep(/rgame.version/)")

    expect(output).to start_with(File.join(ChildRuby::LIB, 'rgame'))
  end

  it 'kills a child that outlives the deadline, and says what it printed' do
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    expect { described_class.capture('$stdout.sync = true; puts "got this far"; sleep 30', timeout: 1) }
      .to raise_error(ChildRuby::Timeout, /within 1s.*got this far/m)
    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 10
  end
end
