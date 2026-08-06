# frozen_string_literal: true

# `allocate_nothing` — a block matcher for the engine's load-bearing rule that the
# per-frame path (a Node's / Component's update, control, draw, and the helpers they
# call) allocates nothing in steady state. See CLAUDE.md "never allocate on the
# per-frame path".
#
#   expect { node.update(dt) }.to allocate_nothing
#   expect { node.draw(renderer) }.to allocate_nothing.over(2_000)
#   expect { component.update(dt) }.to allocate_nothing.after_warmup(50)
#
# How it works: it calls the block a few times to settle one-time lazy allocations
# (hash keys filling in, a CachedLabel building once, a texture being cached), then
# measures the rise in GC.stat(:total_allocated_objects) — a monotonic allocation count —
# across many more calls. Two refinements make the count trustworthy at single-object
# resolution: GC is paused for the window (otherwise a collection triggered mid-measure
# adds its own bookkeeping to the count), and an identical empty-block window is measured
# and subtracted as a baseline (so the measurement harness's own tiny, fixed cost cancels
# out). What remains is purely the block's per-call allocation: zero for a clean path, and
# K × iterations for a per-frame leak of K objects.
#
# Two cautions when using it:
#   - The block must represent a *steady-state* frame: drive it with state that doesn't
#     cross a one-off boundary mid-measurement (e.g. a PathFollow reaching its end and
#     emitting, a pool growing). Pick a dt / setup that keeps it in the repeating case.
#   - Whatever the block touches is measured too, so pass a real, allocation-free fake
#     (a plain object with explicit keyword params, like the fakes in the *_allocation
#     specs) — never an RSpec double, which allocates on every call.
RSpec::Matchers.define :allocate_nothing do
  supports_block_expectations

  # Base number of measured calls. Larger makes a tiny per-frame leak unmistakable.
  chain(:over) { |iterations| @iterations = iterations }
  # Number of unmeasured warm-up calls before measuring, to absorb one-time lazy init.
  chain(:after_warmup) { |warmup| @warmup = warmup }

  match do |block|
    @iterations ||= 1_000
    @warmup ||= 5

    @warmup.times { block.call }

    noop = -> {}
    window = lambda do |callable|
      before = GC.stat(:total_allocated_objects)
      @iterations.times { callable.call }
      GC.stat(:total_allocated_objects) - before
    end

    GC.disable # so a mid-window collection's own allocations don't pollute the count
    begin
      window.call(noop)             # prime anything the first measured window touches once
      baseline = window.call(noop)  # the harness's own fixed per-window cost
      @leaked = window.call(block) - baseline
    ensure
      GC.enable
    end

    @leaked <= 0 # clean path → exactly 0; rounding/noise can only make it slightly negative
  end

  description { "allocate nothing per call (measured over #{@iterations} calls)" }

  failure_message do
    per_call = @leaked.fdiv(@iterations).round(3)
    "expected the block to allocate nothing per call (after #{@warmup} warm-up calls), " \
      "but it allocated #{@leaked} object(s) over #{@iterations} calls (~#{per_call}/call)"
  end

  failure_message_when_negated do
    'expected the block to allocate at least once per call, but it allocated nothing measurable'
  end
end
