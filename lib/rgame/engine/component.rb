# frozen_string_literal: true

module RGame
  module Engine
    class Component
      extend Signal::DSL

      attr_accessor :node

      def context
        @context ||= node.context
      end

      # Tree-lifecycle hooks. on_attach fires once the node is in the live tree, so
      # node.root / node.scene and sibling systems are reachable — pull and register
      # shared systems here, not in initialize (where the node has no anchors yet).
      # on_detach mirrors it: release those registrations.
      def on_attach; end
      def on_detach; end

      # The sibling component this one drives, or a raise naming both — for the
      # `@body = require_sibling(CharacterBody)` line an `on_attach` opens with.
      #
      # Worth a helper rather than a bare `get_component` because the nil it returns
      # is silent, and stays silent until the first frame calls a method on it: the
      # error you see is a NoMethodError on nil, in `control`, naming neither the
      # component that is missing nor the one that wanted it.
      #
      # And the cause is nearly always the same, which is why the message says it.
      # A node assembled *outside* the tree collects every component before any
      # on_attach runs (Node2D#enter_tree), so add order does not matter there. A
      # node that adds components from its own `on_add` is already in the tree, so
      # each one attaches as it arrives and can only see the ones before it. Same
      # two lines, opposite outcome, depending on where they were written.
      def require_sibling(klass)
        node.get_component(klass) ||
          raise("#{self.class} needs a #{klass} on the same node, and there is none. If you did " \
                'add one, add it before this component: a node that is already in the tree ' \
                'attaches each component as it arrives, so a sibling added after this one is ' \
                'not there yet when this one attaches.')
      end

      def control(actions); end
      def update(dt); end
      def draw(renderer, view); end

      # Container components (e.g. SceneStack) that hold nodes off the normal child
      # list override this to forward the deferred-free sweep into them.
      def sweep_freed; end

      # `control` above receives **one player's** Actions — the actions of
      # whoever owns this component's node — which is what a component wants,
      # since it belongs to exactly one node.
      #
      # A container component holding a whole subtree needs the input *source*
      # instead, so the nodes inside it can each resolve their own owner. There
      # is no hook for that on purpose: it is a system lookup like any other, so
      # such a component pulls `node.system(Players)` in `on_attach` and passes
      # that down. SceneStack is the worked example.
    end
  end
end
