# frozen_string_literal: true

require_relative 'hot_path'

module RuboCop
  module Cop
    module Game
      # Flag fresh Array / Range literals that are needless per-frame allocations.
      #
      # Two triggers:
      #  * Anywhere — a literal used as a method-call *receiver*: `[a, b].sum`,
      #    `(a..b).any? { ... }`. Each call allocates the collection just to reduce or
      #    iterate it; compare directly or loop with an index instead.
      #  * Inside a per-frame method (a lifecycle hook or a `# hot-path`-tagged helper) —
      #    *any* Array/Range literal, e.g. returning `[x, y, w, h]` for the caller to
      #    decompose. Expose the parts separately (see `Engine::AnimationSet` row/col/flip_x).
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

        # Sends the VM compiles to `opt_newarray_send`, which builds no Array. The
        # value is the argument count that keeps the optimisation; anything else, or a
        # block, and the compiler falls back to `newarray`.
        OPTIMISED_SENDS = { min: 0, max: 0, hash: 0, include?: 1 }.freeze
        MSG_HOT_PATH = 'Needless %{kind} allocation in a per-frame method: this literal ' \
                       'is built every frame — build it once or expose the parts directly.'

        def on_array(node)
          check(node, 'array')
        end

        def on_irange(node)
          check(node, 'range')
        end

        def on_erange(node)
          check(node, 'range')
        end

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
          return true if node.array_type? && node.children.empty? # []  (mutable-state seed)
          return true if frozen?(node)                            # [...].freeze (once)
          return true if node.parent&.masgn_type?                 # a, b = c, d (no allocation)
          return true if optimised_send?(node)                    # [a, b].min (opt_newarray_send)

          false
        end

        # True for an array literal the VM reduces without building it. Splats are
        # excluded: `[*a, b]` is assembled at runtime by a different path that does
        # allocate, whatever is called on it.
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

        # The send-node the literal is the (possibly parenthesised) receiver of, if any.
        # `(a..b).each` wraps the range in a one-child `begin`, so unwrap that first.
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
