# frozen_string_literal: true

module RGame
  module Engine
    class Component
      extend Signal::DSL
      extend SealedPrivates
      extend Hooks

      attr_accessor :node

      def context
        @context ||= node.context
      end

      # Tree-lifecycle hooks. _attach fires once the node is in the live tree, so
      # node.root / node.scene and sibling systems are reachable — pull and register
      # shared systems here, not in initialize (where the node has no anchors yet).
      # _detach mirrors it: release those registrations.
      def _attach; end
      def _detach; end

      # The sibling component this one drives, or a raise naming both — for the
      # `@body = require_sibling(CharacterBody)` line an `_attach` opens with.
      #
      # Worth a helper rather than a bare `get_component` because the nil it returns
      # is silent, and stays silent until the first frame calls a method on it: the
      # error you see is a NoMethodError on nil, in `_control`, naming neither the
      # component that is missing nor the one that wanted it.
      #
      # And the cause is nearly always the same, which is why the message says it.
      # A node assembled *outside* the tree collects every component before any
      # _attach runs (Node2D#enter_tree), so add order does not matter there. A
      # node that adds components from its own `_enter_tree` is already in the tree, so
      # each one attaches as it arrives and can only see the ones before it. Same
      # two lines, opposite outcome, depending on where they were written.
      #
      # A class several components answer to — `Components::Mover` has three — can match
      # twice on one node, and then there is no telling which one was meant. That raises
      # too, naming each match, rather than quietly taking the first.
      def require_sibling(klass)
        matches = node.components.grep(klass)
        if matches.length > 1
          raise ArgumentError, "#{self.class} reads one #{klass} on the same node, and this node has " \
                               "#{matches.length}: #{matches.map(&:class).join(', ')}. " \
                               'Keep one of them on this node.'
        end

        matches.first ||
          raise("#{self.class} needs a #{klass} on the same node, and there is none. If you did " \
                'add one, add it before this component: a node that is already in the tree ' \
                'attaches each component as it arrives, so a sibling added after this one is ' \
                'not there yet when this one attaches.')
      end

      # The work hooks, named after the node's step that calls them: the node's
      # `control`, `update` and `draw` call each component's hook before the
      # node's own.
      def _control(actions); end
      def _update(dt); end
      def _draw(renderer, view); end

      # Container components (e.g. SceneStack) that hold nodes off the normal child
      # list override this to forward the deferred-free sweep into them.
      def _sweep_freed; end
    end
  end
end
