# frozen_string_literal: true

require_relative 'hot_path'

module RuboCop
  module Cop
    module Game
      # Flag needless per-frame allocations: fresh Array / Range literals, and the
      # iterators that allocate behind the call.
      #
      # Three triggers:
      #  * Anywhere — a literal used as a method-call *receiver*: `[a, b].sum`,
      #    `(a..b).any? { ... }`. Each call allocates the collection just to reduce or
      #    iterate it; compare directly or loop with an index instead.
      #  * Inside a per-frame method (a lifecycle hook or a `# hot-path`-tagged helper) —
      #    *any* Array/Range literal, e.g. returning `[x, y, w, h]` for the caller to
      #    decompose. Expose the parts separately (see `Engine::AnimationSet` row/col/flip_x).
      #  * Inside a per-frame method — an iterator in HIDDEN. Each allocates on every
      #    call although nothing in the line shows it: `each_with_index` one object,
      #    `inject` with a block two, `min_by` two. An Array answers `each_index`,
      #    `sum` and `min` with a block itself, allocating nothing, and HIDDEN names
      #    that answer for each. `inject(:+)`, with no block, allocates nothing.
      #
      # Allowed: an empty `[]` (idiomatic mutable-state seed), a frozen `[...].freeze`
      # (allocated once), a parallel-assignment RHS (`a, b = c, d`, which the VM does
      # not allocate), and the four sends the VM rewrites to `opt_newarray_send`.
      #
      # That last one is not a concession, it is a correction. `[a, b].min` compiles to
      # a single `opt_newarray_send` instruction that reads the operands off the stack
      # and never builds an Array — measured at 0 allocations over 200,000 calls, and
      # visible in `RubyVM::InstructionSequence.compile("[a, b].min").disasm`. Flagging
      # it cost real clarity: `Style/MinMaxComparison` asks for exactly this form, so
      # code was being written around a conflict that does not exist.
      #
      # The optimisation is narrow, which is why OPTIMISED_SENDS is a list rather than a
      # guess. `sum`, `first`, `last` and everything else still emit a plain `newarray`,
      # and even `min` falls back to one the moment it is given a block or an argument
      # (`[a, b].min { ... }`, `[a, b].min(1)`). Ranges never had an Array to build.
      class NoNeedlessAllocation < RuboCop::Cop::Base
        include HotPath

        MSG_RECEIVER = 'Needless %{kind} allocation: this literal is built every call ' \
                       'just to call `%{method}` on it — rewrite without the literal.'

        OPTIMISED_SENDS = { min: 0, max: 0, hash: 0, include?: 1 }.freeze
        MSG_HOT_PATH = 'Needless %{kind} allocation in a per-frame method: this literal ' \
                       'is built every frame — build it once or expose the parts directly.'

        HIDDEN = {
          each_with_index: '`each` with a counter in a local, or `each_index` on an Array',
          each_with_object: '`each`, with the object in a local',
          inject: '`sum`, or `each` with a local',
          reduce: '`sum`, or `each` with a local',
          min_by: '`min` with a block comparing two',
          max_by: '`max` with a block comparing two',
          minmax_by: '`min` and `max` with blocks comparing two',
          minmax: '`min` and `max`',
          each_slice: 'a `while` loop with an index',
          each_cons: 'a `while` loop with an index'
        }.freeze
        BLOCK_ONLY = %i[inject reduce].freeze
        MSG_HIDDEN = '`%{method}` allocates on every call, in a per-frame method. Use %{instead}.'

        def on_array(node)
          check(node, 'array')
        end

        def on_irange(node)
          check(node, 'range')
        end

        def on_erange(node)
          check(node, 'range')
        end

        def on_send(node)
          instead = HIDDEN[node.method_name]
          return if instead.nil? || !in_hot_path?(node)
          return if BLOCK_ONLY.include?(node.method_name) && !node.block_node && !node.block_argument?

          add_offense(node.loc.selector, message: format(MSG_HIDDEN, method: node.method_name, instead: instead))
        end
        alias on_csend on_send

        private

        def check(node, kind)
          return if allowed?(node)

          send = receiving_send(node)
          if send
            add_offense(node, message: format(MSG_RECEIVER, kind: kind, method: send.method_name))
          elsif in_hot_path?(node)
            add_offense(node, message: format(MSG_HOT_PATH, kind: kind))
          end
        end

        def allowed?(node)
          return true if node.array_type? && node.children.empty?
          return true if frozen?(node)
          return true if node.parent&.masgn_type?
          return true if optimised_send?(node)

          false
        end

        def optimised_send?(node)
          return false unless node.array_type?
          return false if node.children.any?(&:splat_type?)

          send = receiving_send(node)
          return false if send.nil? || send.block_node

          arity = OPTIMISED_SENDS[send.method_name]
          !arity.nil? && send.arguments.size == arity
        end

        def frozen?(node)
          send = receiving_send(node)
          send&.method?(:freeze)
        end

        def receiving_send(node)
          receiver = node
          parent = node.parent
          if parent&.begin_type? && parent.children.one?
            receiver = parent
            parent = parent.parent
          end
          return unless parent&.send_type? && parent.receiver == receiver

          parent
        end

        def in_hot_path?(node)
          enclosing = node.each_ancestor(:def).first
          enclosing && hot_path_def?(enclosing)
        end
      end
    end
  end
end
