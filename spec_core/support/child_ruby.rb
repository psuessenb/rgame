# frozen_string_literal: true

require 'open3'

# Runs a Ruby script in a child process with this checkout's `lib/` on the load
# path, and kills it if it has not exited within a deadline.
#
# Every Core spec that needs a fresh process goes through here. Those children
# open real windows and run real loops, and one that never exits would
# otherwise hold the suite for as long as CI lets a job run: a stalled
# `game.start` on a Windows runner once kept a job busy for 51 minutes. With a
# deadline the example fails with what the child printed, and the suite goes on.
module ChildRuby
  LIB = File.expand_path('../../lib', __dir__)

  # A child that opens a window and exits takes under a second; the docs checks,
  # which load all three layers, take a few. A minute is a hang, not a slow run.
  TIMEOUT = 60

  # The child did not exit in time, and was killed.
  class Timeout < StandardError; end

  class << self
    # Runs `script`, with any further arguments as its ARGV, and returns
    # `[stdout, stderr, status]`, as `Open3.capture3` does. Raises
    # `ChildRuby::Timeout`, carrying the output so far, when the child outlives
    # `timeout` seconds.
    def capture(script, *, env: {}, chdir: Dir.pwd, timeout: TIMEOUT)
      Open3.popen3(env, RbConfig.ruby, '-I', LIB, '-e', script, *, chdir: chdir) do |stdin, stdout, stderr, wait|
        stdin.close
        output = Thread.new { stdout.read }
        errors = Thread.new { stderr.read }
        kill(wait, output, errors, timeout) unless wait.join(timeout)
        [output.value, errors.value, wait.value]
      end
    end

    private

    def kill(wait, output, errors, timeout)
      Process.kill('KILL', wait.pid)
      wait.join
      raise Timeout, "child ruby did not exit within #{timeout}s and was killed. " \
                     "It printed:\n#{output.value}#{errors.value}"
    end
  end
end
