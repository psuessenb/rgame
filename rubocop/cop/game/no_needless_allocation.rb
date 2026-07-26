# frozen_string_literal: true

require_relative 'hot_path'

module RuboCop
  module Cop
    module Game
      # Flag fresh Array / Range literals that are needless per-frame allocations.
      #
      # Two triggers:
      #  * Anywhere — a literal used as a method-call *receiver*: `[a, b].max`,
      #    `(a..b).any? { ... }`. Each call allocates the collection just to reduce or
      #    iterate it; compare directly or loop with an index instead.
      #  * Inside a per-frame method (a lifecycle hook or a `# hot-path`-tagged helper) —
      #    *any* Array/Range literal, e.g. returning `[x, y, w, h]` for the caller to
      #    decompose. Expose the parts separately (see `Engine::AnimationSet` row/col/flip_x).
      #
      # Allowed: an empty `[]` (idiomatic mutable-state seed), a frozen `[...].freeze`
      # (allocated once), and a parallel-assignment RHS (`a, b = c, d`, which the VM does
      # not allocate).
      class NoNeedlessAllocation < RuboCop::Cop::Base
        include HotPath

        MSG_RECEIVER = 'Needless %{kind} allocation: this literal is built every call ' \
                       'just to call `%{method}` on it — rewrite without the literal.'
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

          false
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
