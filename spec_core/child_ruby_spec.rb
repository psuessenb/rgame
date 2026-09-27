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

  # The grandchild inherits the child's stdout and outlives it, so the pipe
  # stays open after the child exits. On Unix the kill takes the grandchild
  # with it. On Windows it cannot, since its parent is gone, and it sleeps out
  # its 15 seconds.
  it 'gives up on output that stays open after the child exits' do
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    script = "$stdout.sync = true; puts 'before the grandchild'; spawn(RbConfig.ruby, '-e', 'sleep 15')"

    expect { described_class.capture(script, timeout: 1) }
      .to raise_error(ChildRuby::Timeout, /still open after 1s.*before the grandchild/m)
    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 10
  end
end
