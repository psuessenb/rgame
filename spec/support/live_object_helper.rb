# frozen_string_literal: true

# Counting a C extension's live objects back to a baseline, for specs.
#
# A class with a `debug_live_*` counter (incremented where it allocates, decremented in its
# `dfree`) is checked by building a batch and collecting it: the count must come back to where
# it started. What makes that hard to state exactly is Ruby's collector, which scans the machine
# stack *conservatively* — any word there that looks like a pointer to an object keeps the
# object alive. A C frame that has returned leaves its words behind, and the frames `GC.start`
# pushes into the same stretch of stack do not always overwrite them, so the last object a loop
# built can survive the collection. It depends on the compiler's frame layout: measured on this
# project's CI as exactly one survivor on Linux and on Windows, and none on a developer
# machine running the same code.
#
# `build_in_finished_thread` runs the allocating block on a thread and joins it. Once the thread
# has ended its stack is no longer scanned, so no stale word can point at what it built, and
# the count is exact again on every platform.
module LiveObjectHelper
  def collect_garbage = 3.times { GC.start(full_mark: true, immediate_sweep: true) }

  def build_in_finished_thread(&)
    Thread.new(&).join
    nil
  end
end

RSpec.configure { |config| config.include LiveObjectHelper }
