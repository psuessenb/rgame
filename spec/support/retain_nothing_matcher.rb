# frozen_string_literal: true

require 'objspace'

# `retain_nothing` — a block matcher for the other half of the allocation rule:
# whatever the block allocates, none of it outlives the block.
#
#   expect { scene.update(dt) }.to retain_nothing
#   expect { tick }.to retain_nothing.over(5_000).after_warmup(120)
#
# `allocate_nothing` asks how often the collector runs. This asks what it finds
# when it does. A minor collection sweeps an object that died young, cheaply. An
# object that survives three collections joins the old generation, and a growing
# old generation is what schedules a full collection: the pause a player sees.
# So a block may allocate and still pass here. A block that keeps one object in
# a hundred calls fails, however rarely the collector happens to run.
#
# How it works: it calls the block to settle any growth that stops, such as a
# cache filling or a pool reaching its high-water mark. Then it collects fully,
# runs the block `over` times, collects fully again, and compares the number of
# live objects. The calls run on a thread that has ended before the second
# collection. Ruby scans the machine stack conservatively, and a stale word
# there could keep the last object alive; see LiveObjectHelper. An empty block
# measured the same way is subtracted, so the harness's own cost cancels out. A
# failure runs the block once more with allocation tracing on, and names the
# lines the survivors came from.
#
# The warm-up is the one thing to get right. It must carry the block past every
# growth that stops. A pool still growing during the window fails the match,
# which is correct only if the window was meant to be steady state.
RSpec::Matchers.define :retain_nothing do
  include LiveObjectHelper

  supports_block_expectations

  # Number of measured calls. A path that keeps K objects per call keeps K × this.
  chain(:over) { |iterations| @iterations = iterations }
  # Number of unmeasured calls first, to carry the block past growth that stops.
  chain(:after_warmup) { |warmup| @warmup = warmup }

  match do |block|
    @iterations ||= 1_000
    @warmup ||= 5
    @warmup.times { block.call }

    noop = -> {}
    retained_by(noop)
    baseline = retained_by(noop)
    @retained = retained_by(block) - baseline
    @sites = survivor_sites(block) if @retained.positive?
    @retained <= 0
  end

  def retained_by(callable)
    collect_garbage
    before = GC.stat(:heap_live_slots)
    build_in_finished_thread { @iterations.times { callable.call } }
    collect_garbage
    GC.stat(:heap_live_slots) - before
  end

  def survivor_sites(callable)
    ObjectSpace.trace_object_allocations_start
    collect_garbage
    generation = GC.count
    build_in_finished_thread { @iterations.times { callable.call } }
    collect_garbage
    tally_sites(generation)
  ensure
    ObjectSpace.trace_object_allocations_stop
    ObjectSpace.trace_object_allocations_clear
  end

  def tally_sites(generation)
    sites = Hash.new(0)
    ObjectSpace.each_object do |object|
      file = ObjectSpace.allocation_sourcefile(object)
      next if file.nil? || file == __FILE__
      next if ObjectSpace.allocation_generation(object) < generation

      line = ObjectSpace.allocation_sourceline(object)
      sites["#{ObjectSpace.internal_class_of(object)} at #{file}:#{line}"] += 1
    end
    sites.sort_by { -it.last }.first(10)
  end

  description { "retain nothing (measured over #{@iterations} calls)" }

  failure_message do
    listed = @sites.map { |site, count| "  #{count} #{site}" }.join("\n")
    "expected nothing the block allocated to outlive it (after #{@warmup} warm-up calls), " \
      "but #{@retained} object(s) did over #{@iterations} calls " \
      "(~#{@retained.fdiv(@iterations).round(3)}/call). Traced survivors:\n#{listed}"
  end

  failure_message_when_negated do
    'expected the block to keep at least one object it allocated, but it kept nothing measurable'
  end
end
