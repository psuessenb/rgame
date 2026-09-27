# frozen_string_literal: true

require 'open3'

# Runs a Ruby script in a child process with this checkout's `lib/` on the load
# path, and kills it if it has not finished within a deadline.
#
# Every Core spec that needs a fresh process goes through here. Those children
# open real windows and run real loops, and one that never exits would
# otherwise hold the suite for as long as CI lets a job run: a stalled
# `game.start` on a Windows runner once kept a job busy for 51 minutes. With a
# deadline the example fails with what the child printed, and the suite goes on.
#
# The child has finished only when it has exited and closed its output. Any
# process it started can inherit that output and hold it open after the child
# exits, so the deadline covers both. When it passes, `capture` kills the
# child's whole process tree and waits a few more seconds at most. It raises
# even if the kill failed, and lists the processes still running, so a hang
# says what hung rather than holding the job until CI cancels it.
module ChildRuby
  LIB = File.expand_path('../../lib', __dir__)

  # A child that opens a window and exits takes under a second; the docs checks,
  # which load all three layers, take a few. A minute is a hang, not a slow run.
  TIMEOUT = 60

  # How long a killed child gets to exit and let go of its output.
  GRACE = 5

  WINDOWS = Gem.win_platform?

  # The child did not finish in time, and was killed.
  class Timeout < StandardError; end

  class << self
    # Runs `script`, with any further arguments as its ARGV, and returns
    # `[stdout, stderr, status]`, as `Open3.capture3` does. Raises
    # `ChildRuby::Timeout`, carrying the output so far, when the child has not
    # exited and closed its output within `timeout` seconds.
    def capture(script, *, env: {}, chdir: Dir.pwd, timeout: TIMEOUT)
      stdin, stdout, stderr, wait = Open3.popen3(env, RbConfig.ruby, '-I', LIB, '-e', script, *,
                                                 chdir: chdir, **own_group)
      stdin.close
      output = ''.b
      errors = ''.b
      readers = [read_into(output, stdout), read_into(errors, stderr)]
      deadline = now + timeout
      exited = wait.join(timeout)
      closed = exited && readers.all? { |reader| reader.join([deadline - now, 0].max) }
      give_up(wait, readers, output, errors, timeout, exited) unless closed
      [text(output), text(errors), wait.value]
    ensure
      [stdout, stderr].each { |io| io&.close unless io&.closed? }
    end

    private

    # On Unix the child leads a process group of its own, so a kill of the group
    # reaches every process it started.
    def own_group = WINDOWS ? {} : { pgroup: true }

    def read_into(buffer, io)
      Thread.new do
        loop { buffer << io.readpartial(4096) }
      rescue IOError
        buffer
      end
    end

    # What `IO#read` would have returned: `readpartial` reads bytes, and skips
    # the CRLF conversion text mode does on Windows.
    def text(bytes)
      string = bytes.dup.force_encoding(Encoding.default_external).scrub
      WINDOWS ? string.gsub("\r\n", "\n") : string
    end

    def give_up(wait, readers, output, errors, timeout, exited)
      running = processes(wait.pid)
      kill_tree(wait.pid)
      dead = wait.join(GRACE)
      grace_ends = now + GRACE
      readers.each { |reader| reader.join([grace_ends - now, 0].max) || reader.kill }
      raise Timeout, "child ruby #{wait.pid} #{outcome(exited, dead, timeout)}\n" \
                     "Processes when the deadline passed:\n#{running}" \
                     "It printed:\n#{text(output)}#{text(errors)}"
    end

    def outcome(exited, dead, timeout)
      if exited then "exited, but its output was still open after #{timeout}s."
      elsif dead then "did not exit within #{timeout}s and was killed."
      else "did not exit within #{timeout}s, and was still running #{GRACE}s after it was killed."
      end
    end

    def kill_tree(pid)
      if WINDOWS
        system('taskkill', '/T', '/F', '/PID', pid.to_s, out: File::NULL, err: File::NULL)
      else
        Process.kill('KILL', -pid)
      end
    rescue Errno::ESRCH
      nil
    end

    # Every Ruby, and anything reporting a crash on Windows, since the child's
    # own process may already have gone. Not `tasklist /V`: it asks every window
    # for its title, which took 14 seconds on a desktop with none hung.
    def processes(pid)
      command = WINDOWS ? %w[tasklist /FO CSV] : %w[ps -A -o pid,ppid,stat,etime,args]
      listing, = Open3.capture2(*command, binmode: true)
      header, *rows = listing.encode('UTF-8', invalid: :replace, undef: :replace).lines
      wanted = rows.grep(/ruby|werfault|#{pid}/i)
      [header, *wanted].join
    rescue SystemCallError => e
      "(could not list them: #{e.message})"
    end

    def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
